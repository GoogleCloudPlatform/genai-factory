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
  registry_uri = "//agentregistry.googleapis.com/projects/${var.project_id}/locations/${var.region}"

  policy_files = fileset(path.module, "policies/*.yaml")

  template_vars = {
    project_id                        = var.project_id
    region                            = var.region
    model_armor_request_template_id  = var.model_armor_request_template_id
    model_armor_response_template_id = var.model_armor_response_template_id
    model_armor_authz_hosts           = var.model_armor_authz_hosts
  }

  policies = {
    for f in local.policy_files :
    replace(basename(f), ".yaml", "") => yamldecode(templatefile("${path.module}/${f}", local.template_vars))
    if !(replace(basename(f), ".yaml", "") == "model_armor" && !var.enable_model_armor)
  }

  service_extensions_sa        = try(module.agent_gateway.agent_gateway.agent_gateway_card[0].service_extensions_service_account, "")
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
}

# Create the Network Attachment in the Service Project pointing to the Host Subnet
resource "google_compute_network_attachment" "agent_gateway" {
  name                  = "${var.prefix}-${var.name}-gateway-na"
  project               = var.project_id
  region                = var.region
  connection_preference = "ACCEPT_MANUAL"
  subnetworks           = [var.networking_config.subnet]

  lifecycle {
    ignore_changes = [producer_accept_lists]
  }
}

# Provision the Egress Agent Gateway
module "agent_gateway" {
  source      = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/agent-gateway?ref=v57.0.0"
  project_id  = var.project_id
  region      = var.region
  name        = "${var.prefix}-${var.name}-gateway"
  access_path = "AGENT_TO_ANYWHERE"
  registries  = [local.registry_uri]
  networking_config = {
    psc_i_network_attachment_id = google_compute_network_attachment.agent_gateway.id
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
}

# Dynamic Authz Extensions
resource "google_network_services_authz_extension" "custom" {
  for_each  = local.policies
  provider  = google-beta
  project   = var.project_id
  name      = "${var.prefix}-${var.name}-${replace(each.key, "_", "-")}-authz"
  location  = var.region
  service   = each.value.service
  timeout   = try(each.value.timeout, "2s")
  fail_open = try(each.value.fail_open, true)

  metadata = merge(
    try(each.value.metadata, {}),
    try(each.value.model_armor_settings, null) != null ? {
      model_armor_settings = jsonencode([each.value.model_armor_settings])
    } : {}
  )
}

# Dynamic Authz Policies
resource "google_network_security_authz_policy" "custom" {
  for_each       = local.policies
  depends_on     = [time_sleep.wait_for_gateway]
  provider       = google-beta
  project        = var.project_id
  name           = "${var.prefix}-${var.name}-${replace(each.key, "_", "-")}-policy"
  location       = var.region
  policy_profile = each.value.policy_profile
  action         = "CUSTOM"

  target {
    resources = [module.agent_gateway.id]
  }

  custom_provider {
    authz_extension {
      resources = [google_network_services_authz_extension.custom[each.key].id]
    }
  }

  dynamic "http_rules" {
    for_each = try(each.value.http_rules, null) != null ? each.value.http_rules : []
    content {
      to {
        operations {
          dynamic "hosts" {
            for_each = http_rules.value.hosts != null ? http_rules.value.hosts : []
            content {
              exact = hosts.value
            }
          }
        }
      }
    }
  }
}




