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

# tfdoc:file:description Egress Agent Gateway and its authorization policies.

locals {
  _agw_model_armor = var.agent_gateway_config.egress.model_armor_config
  _agw_networking  = var.agent_gateway_config.egress.networking

  agw_dns_peering_config = (
    local._agw_networking.dns_peering_config == null
    ? null
    : {
      domain = local._agw_networking.dns_peering_config.domain
      target_network = coalesce(
        local._agw_networking.dns_peering_config.target_network,
        local.vpc
      )
    }
  )

  vpc = lookup(
    var.vpc_self_links, var.networking_config.vpc, var.networking_config.vpc
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

# Create the egress Agent Gateway, its agent connectivity template,
# the IAP and Model Armor authorization policies, and the Agent
# Registry IAM bindings authorizing agent egress.
module "agent_gateway_egress" {
  source         = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/geap-agent-gateway?ref=v59.0.0"
  project_id     = var.project_id
  project_number = var.number
  region         = var.region
  name           = var.name
  access_path    = "AGENT_TO_ANYWHERE"
  # Registry locations default to regional
  registries = [
    for registry_type in var.agent_gateway_config.egress.registry_locations
    : local.agent_registry_uris[registry_type]
  ]
  # The gateway reaches the VPC through an agent connectivity
  # template, which the module manages on our behalf. The attachment
  # is passed through the context, so that the template resource
  # count stays known while Terraform still orders the two.
  networking_config = {
    access_types                = local._agw_networking.access_types
    dns_peering_config          = local.agw_dns_peering_config
    psc_i_network_attachment_id = "$psc_network_attachments:${var.name}"
    vpc_egress                  = local._agw_networking.vpc_egress
  }
  context = {
    psc_network_attachments = {
      (var.name) = google_compute_network_attachment.agw_network_attachment.id
    }
  }
  iap_config = {
    fail_open            = var.agent_gateway_config.egress.iap.fail_open
    iam_enforcement_mode = var.agent_gateway_config.egress.iap.iam_enforcement_mode
    policy_version       = var.agent_gateway_config.egress.iap.policy_version
    timeout              = var.agent_gateway_config.egress.iap.timeout
  }
  model_armor_config = (
    local._agw_model_armor.enable
    ? {
      authz_hosts = local._agw_model_armor.authz_hosts
      fail_open   = local._agw_model_armor.fail_open
      request_template_id = google_model_armor_template.default[
        local._agw_model_armor.request_direction
      ].name
      response_template_id = google_model_armor_template.default[
        local._agw_model_armor.response_direction
      ].name
      timeout = local._agw_model_armor.timeout
    }
    : null
  )
  registry_iam                   = var.agent_registry_iam
  registry_iam_bindings          = local.registry_iam_bindings
  registry_iam_bindings_additive = local.registry_iam_bindings_additive
  registry_iam_by_principals     = var.agent_registry_iam_by_principals
}
