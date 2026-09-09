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
  subnetwork = lookup(
    var.subnet_self_links, var.networking_config.subnet, var.networking_config.subnet
  )
}

# Network attachment for Agent Gateway PSC-I
resource "google_compute_network_attachment" "agw_network_attachment" {
  name                  = var.name
  project               = var.project_id
  region                = var.region
  connection_preference = "ACCEPT_MANUAL"
  subnetworks           = [local.subnetwork]
  producer_accept_lists = [var.project_id]

  lifecycle {
    ignore_changes = [producer_accept_lists]
  }
}

# Create egress Agent Gateway
module "agent_gateway_egress" {
  source      = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/agent-gateway?ref=v58.0.0"
  project_id  = var.project_id
  region      = var.region
  name        = var.name
  access_path = "AGENT_TO_ANYWHERE"
  registries  = [local.registry_uri]
  networking_config = {
    psc_i_network_attachment_id = google_compute_network_attachment.agw_network_attachment.id
  }
}

# Wait for Agent Gateway to stabilize before attaching authz policies.
resource "time_sleep" "wait_for_gateway_egress" {
  depends_on      = [module.agent_gateway_egress]
  create_duration = "30s"

  triggers = {
    gateway_id = module.agent_gateway_egress.id
  }
}

# IAP service extension.
resource "google_network_services_authz_extension" "iap_auth_srv_ext" {
  name      = var.name
  project   = var.project_id
  location  = var.region
  service   = "iap.googleapis.com"
  timeout   = var.agent_gateway_config.iap.timeout
  fail_open = var.agent_gateway_config.iap.fail_open

  metadata = merge(
    { iapPolicyVersion = var.agent_gateway_config.iap.policy_version },
    var.agent_gateway_config.iap.iam_enforcement_mode == null ? {} : {
      iamEnforcementMode = var.agent_gateway_config.iap.iam_enforcement_mode
    }
  )
}

# Create a policy to bind the IAP service extension to the Agent Gateway.
resource "google_network_security_authz_policy" "iap_authz_policy" {
  name           = var.name
  project        = var.project_id
  location       = var.region
  policy_profile = "REQUEST_AUTHZ"
  action         = "CUSTOM"

  target {
    resources = [module.agent_gateway_egress.id]
  }

  custom_provider {
    authz_extension {
      resources = [
        google_network_services_authz_extension.iap_auth_srv_ext.id
      ]
    }
  }

  depends_on = [time_sleep.wait_for_gateway_egress]
}
