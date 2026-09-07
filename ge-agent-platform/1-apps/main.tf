# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

locals {
  # Flatten each Google API into its endpoint variants (global, mTLS, locational, locational mTLS, and regional REP), keyed by service_id.
  google_api_variants = merge([
    for id, name in var.google_apis : {
      (length(id) >= 4 ? id : "${id}-endpoint") = {
        display_name = name
        url          = "https://${id}.googleapis.com"
      }
      "${id}-mtls" = {
        display_name = "${name} mTLS"
        url          = "https://${id}.mtls.googleapis.com"
      }
      "${var.region}-${id}" = {
        display_name = "${name} Locational"
        url          = "https://${var.region}-${id}.googleapis.com"
      }
      "${var.region}-${id}-mtls" = {
        display_name = "${name} Locational mTLS"
        url          = "https://${var.region}-${id}.mtls.googleapis.com"
      }
      "${id}-${var.region}-rep" = {
        display_name = "${name} Regional (REP)"
        url          = "https://${id}.${var.region}.rep.googleapis.com"
      }
    }
  ]...)
  registry_uri          = "//agentregistry.googleapis.com/projects/${var.project_id}/locations/${var.region}"
  service_extensions_sa = try(module.agent_gateway.agent_gateway.agent_gateway_card[0].service_extensions_service_account, "")
}

# Create the Network Attachment in the Service Project pointing to the Host Subnet
resource "google_compute_network_attachment" "network_attachment" {
  name                  = "${var.name}-gateway-network-attachment"
  project               = var.project_id
  region                = var.region
  connection_preference = "ACCEPT_MANUAL"
  subnetworks           = [var.networking_config.subnet]
  producer_accept_lists = [var.project_id]

  lifecycle {
    ignore_changes = [producer_accept_lists]
  }
}

# Provision the Egress Agent Gateway
module "agent_gateway" {
  source      = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/agent-gateway?ref=v58.0.0"
  project_id  = var.project_id
  region      = var.region
  name        = "${var.name}-gateway"
  access_path = var.agent_gateway_config.access_path
  registries  = [local.registry_uri]
  networking_config = {
    psc_i_network_attachment_id = google_compute_network_attachment.network_attachment.id
  }
}

# Google API endpoints registered in Agent Registry
resource "google_agent_registry_service" "google_apis" {
  for_each     = local.google_api_variants
  provider     = google-beta
  project      = var.project_id
  location     = var.region
  service_id   = each.key
  display_name = each.value.display_name

  interfaces {
    url              = each.value.url
    protocol_binding = "JSONRPC"
  }

  endpoint_spec {
    type = "NO_SPEC"
  }
}

# Custom service endpoints registered in Agent Registry
resource "google_agent_registry_service" "custom" {
  for_each     = { for svc in var.custom_services : svc.id => svc }
  provider     = google-beta
  project      = var.project_id
  location     = var.region
  service_id   = each.key
  display_name = each.value.display_name
  description  = try(each.value.description, null)

  interfaces {
    url              = each.value.url
    protocol_binding = "JSONRPC"
  }

  endpoint_spec {
    type = "NO_SPEC"
  }
}

# Allow the Agent Gateway control plane / tenant project to stabilize before
# attaching authz policies. Without this, the backend may return a 400/409
# 'resource is being created and therefore can not be updated' error.
resource "time_sleep" "wait_for_gateway" {
  depends_on      = [module.agent_gateway]
  create_duration = "30s"

  triggers = {
    gateway_id = module.agent_gateway.id
  }
}

# IAP REQUEST_AUTHZ service extension. The Agent Gateway calls IAP per request
# to evaluate the agent identity's IAM allow policy on the target.
resource "google_network_services_authz_extension" "iap" {
  provider  = google-beta
  project   = var.project_id
  name      = "${var.name}-iap-authz-ext"
  location  = var.region
  service   = "iap.googleapis.com"
  timeout   = try(var.agent_gateway_config.iap.timeout, "2s")
  fail_open = try(var.agent_gateway_config.iap.fail_open, true)

  metadata = merge(
    {
      iapPolicyVersion = coalesce(try(var.agent_gateway_config.iap.policy_version, null), "V2")
    },
    try(var.agent_gateway_config.iap.iam_enforcement_mode, null) != null ? {
      iamEnforcementMode = var.agent_gateway_config.iap.iam_enforcement_mode
    } : {}
  )
}

# Bind the IAP authz extension to the Agent Gateway. REQUEST_AUTHZ profile
# evaluates once per request at the headers stage.
resource "google_network_security_authz_policy" "iap" {
  depends_on     = [time_sleep.wait_for_gateway]
  provider       = google-beta
  project        = var.project_id
  name           = "${var.name}-iap-policy"
  location       = var.region
  policy_profile = "REQUEST_AUTHZ"
  action         = "CUSTOM"

  target {
    resources = [module.agent_gateway.id]
  }

  custom_provider {
    authz_extension {
      resources = [google_network_services_authz_extension.iap.id]
    }
  }
}

# Model Armor CONTENT_AUTHZ service extension. Regional REP endpoint —
# constructed from var.region. The extension passes the request/response
# templates as opaque metadata that Model Armor's callout reads at evaluation
# time.
resource "google_network_services_authz_extension" "model_armor" {
  count     = try(var.agent_gateway_config.model_armor.enable, false) ? 1 : 0
  provider  = google-beta
  project   = var.project_id
  name      = "${var.name}-ma-authz"
  location  = var.region
  service   = "modelarmor.${var.region}.rep.googleapis.com"
  timeout   = try(var.agent_gateway_config.model_armor.timeout, "2s")
  fail_open = try(var.agent_gateway_config.model_armor.fail_open, true)

  metadata = {
    "model_armor_settings" = jsonencode([{
      request_template_id  = google_model_armor_template.request[0].name
      response_template_id = google_model_armor_template.response[0].name
    }])
  }
}

# Bind the Model Armor authz extension to the Agent Gateway. CONTENT_AUTHZ
# profile streams body events to the extension for content sanitization.
# When model_armor.authz_hosts is non-empty, scope the policy to the listed
# Host header values via http_rules; otherwise the policy applies to all
# gateway traffic.
# Serialized after the IAP authz policy: both policies attach to the same Agent
# Gateway, and the gateway backend allows only one mutating operation at a time
# (concurrent creates fail with code 10 "another ongoing operation for the same
# AgentGateway"). depends_on forces them to apply sequentially.
resource "google_network_security_authz_policy" "model_armor" {
  depends_on     = [time_sleep.wait_for_gateway, google_network_security_authz_policy.iap]
  count          = try(var.agent_gateway_config.model_armor.enable, false) ? 1 : 0
  provider       = google-beta
  project        = var.project_id
  name           = "${var.name}-ma-policy"
  location       = var.region
  policy_profile = "CONTENT_AUTHZ"
  action         = "CUSTOM"

  target {
    resources = [module.agent_gateway.id]
  }

  custom_provider {
    authz_extension {
      resources = [google_network_services_authz_extension.model_armor[0].id]
    }
  }

  dynamic "http_rules" {
    for_each = length(try(var.agent_gateway_config.model_armor.authz_hosts, [])) > 0 ? [1] : []
    content {
      to {
        operations {
          dynamic "hosts" {
            for_each = var.agent_gateway_config.model_armor.authz_hosts
            content {
              exact = hosts.value
            }
          }
        }
      }
    }
  }
}
