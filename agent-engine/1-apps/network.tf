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
  network_attachment_id = (
    var.networking_config.create
    ? google_compute_network_attachment.network_attachment[0].id
    : var.networking_config.network_attachment_id
  )
  subnet_id = (
    var.networking_config.create
    ? module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
    : var.networking_config.subnet.name
  )
  proxy_ip = (
    var.networking_config.create
    ? cidrhost(var.networking_config.subnet.ip_cidr_range, 100)
    : var.networking_config.proxy_ip
  )
  vpc_id = (
    var.networking_config.create
    ? module.vpc[0].id
    : var.networking_config.vpc_id
  )
  vpc_name = (
    var.networking_config.create
    ? module.vpc[0].name
    : element(split("/", var.networking_config.vpc_id), -1)
  )
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v51.0.0"
  count      = var.networking_config.create ? 1 : 0
  project_id = var.project_config.id
  name       = var.networking_config.vpc_id
  subnets = [
    merge(var.networking_config.subnet, { region = var.region })
  ]
  subnets_proxy_only = [
    merge(var.networking_config.subnet_proxy_only, { region = var.region })
  ]
}

# DNS policies for Google APIs
module "dns_policy_googleapis" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns-response-policy?ref=v51.0.0"
  count      = var.networking_config.create ? 1 : 0
  project_id = var.project_config.id
  name       = "googleapis"
  factories_config = {
    rules = "./data/dns-policy-rules.yaml"
  }
  networks = { (var.name) = module.vpc[0].id }
}

# This is a minimal Secure Web Proxy (SWP) setup.
# An explicit proxy is required for Agent Engines using PSC-I
# to go to the Internet. You can substitute this with your favorite proxy.
module "secure-web-proxy" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-swp"
  count      = var.networking_config.create ? 1 : 0
  project_id = var.project_config.id
  region     = var.region
  name       = var.name
  network    = module.vpc[0].id
  subnetwork = module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
  gateway_config = {
    addresses = [local.proxy_ip]
  }
  policy_rules = {
    host-0 = {
      priority        = 1000
      allow           = true
      session_matcher = "host() == 'api.frankfurter.app'"
    }
  }
}

resource "google_compute_network_attachment" "network_attachment" {
  count                 = var.networking_config.create ? 1 : 0
  name                  = var.name
  project               = var.project_config.id
  region                = var.region
  description           = "Network attachment for Agent Engine PSC-I"
  connection_preference = "ACCEPT_MANUAL"
  subnetworks = [
    local.subnet_id
  ]
}
