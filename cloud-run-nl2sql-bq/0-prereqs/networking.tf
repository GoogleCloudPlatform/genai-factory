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
  multi_region = startswith(var.region, "europe") ? "eu" : "us"
  rep_endpoints = var.networking_config.create ? {
    aiplatform-mrep = "aiplatform.${local.multi_region}.rep.googleapis.com"
  } : {}
}

module "vpc" {
  count      = var.networking_config.create ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v59.1.0"
  project_id = module.projects.projects["host"].project_id
  name       = var.networking_config.vpc_name
  subnets = [
    merge(var.networking_config.subnet, { region = var.region })
  ]
  subnets_proxy_only = [
    merge(var.networking_config.subnet_proxy_only, { region = var.region })
  ]
  shared_vpc_host = true
  shared_vpc_service_projects = [
    module.projects.project_ids["service-01"]
  ]
}

# Regional PSC endpoints for regional and multi-regional Google APIs
resource "google_network_connectivity_regional_endpoint" "rep" {
  for_each          = local.rep_endpoints
  project           = module.projects.projects["host"].project_id
  name              = "${var.networking_config.vpc_name}-${each.key}"
  location          = var.region
  target_google_api = each.value
  access_type       = "REGIONAL"
  network           = module.vpc[0].id
  subnetwork = (
    module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
  )
}

# DNS policies for Google APIs
module "dns_policy_googleapis" {
  count      = var.networking_config.create ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns-response-policy?ref=v59.1.0"
  project_id = module.projects.projects["host"].project_id
  name       = "googleapis"
  factories_config = {
    rules = "./data/dns-policy-rules.yaml"
  }
  rules = {
    for k, v in local.rep_endpoints : k => {
      dns_name = "${v}."
      local_data = {
        A = {
          rrdatas = [
            google_network_connectivity_regional_endpoint.rep[k].address
          ]
        }
      }
    }
  }
  networks = { vpc = module.vpc[0].id }
}
