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

module "vpc" {
  count      = var.networking_config.create ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v55.4.0"
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

# DNS policies for Google APIs
module "dns_policy_googleapis" {
  count      = var.networking_config.create ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns-response-policy?ref=v55.4.0"
  project_id = module.projects.projects["host"].project_id
  name       = "googleapis"
  factories_config = {
    rules = "./data/dns-policy-rules.yaml"
  }
  networks = { vpc = module.vpc[0].id }
}

# This is a minimal Secure Web Proxy (SWP) setup.
# An explicit proxy is required for Agent Engines using PSC-I
# to go to the Internet. You can substitute this with your favorite proxy.
module "secure-web-proxy" {
  count        = var.networking_config.create ? 1 : 0
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-swp?ref=v55.4.0"
  project_id   = module.projects.projects["host"].project_id
  region       = var.region
  name         = "proxy-0"
  network      = module.vpc[0].id
  subnetwork   = module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
  policy_rules = var.networking_config.proxy_config.policy_rules
  gateway_config = {
    addresses = [var.networking_config.proxy_config.ip_address]
    ports     = [var.networking_config.proxy_config.port]
  }
}

resource "google_compute_network_attachment" "network_attachment" {
  count                 = var.networking_config.create ? 1 : 0
  name                  = var.prefix
  project               = module.projects.projects["host"].project_id
  region                = var.region
  description           = "Network attachment for Agent Engine PSC-I"
  connection_preference = "ACCEPT_MANUAL"
  subnetworks = [
    module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
  ]

  # Agent Engine SA automatically populates this when PSC-I is active.
  # It adds the tenant project id.
  lifecycle {
    ignore_changes = [producer_accept_lists]
  }
}
