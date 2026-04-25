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
  subnet_id = (
    var.networking_config.create
    ? module.vpc[0].subnet_ids["${var.regions.resources}/${var.networking_config.subnet.name}"]
    : var.networking_config.subnet.name
  )
  vpc_id = (
    var.networking_config.create
    ? module.vpc[0].id
    : var.networking_config.vpc_id
  )
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v55.2.0"
  count      = var.networking_config.create ? 1 : 0
  project_id = var.project_config.id
  name       = var.networking_config.vpc_id
  subnets = [
    merge(var.networking_config.subnet, { region = var.regions.resources })
  ]
  subnets_proxy_only = [
    merge(var.networking_config.subnet_proxy_only, { region = var.regions.resources })
  ]
}

# DNS policies for Google APIs
module "dns_policy_googleapis" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns-response-policy?ref=v55.2.0"
  count      = var.networking_config.create ? 1 : 0
  project_id = var.project_config.id
  name       = "googleapis"
  factories_config = {
    rules = "./data/dns-policy-rules.yaml"
  }
  networks = { (var.name) = module.vpc[0].id }
}

module "firewall-policy" {
  count     = var.service_directory_configs.create_firewall_policy_rule ? 1 : 0
  source    = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-firewall-policy?ref=v55.2.0"
  name      = var.name
  parent_id = var.project_config.id
  region    = "global"
  attachments = {
    vpc = local.vpc_id
  }
  egress_rules = {}
  ingress_rules = {
    allow-service-directory = {
      priority = 1000
      match = {
        source_ranges = ["35.199.192.0/19"]
        layer4_configs = [{
          protocol = "tcp"
          ports    = [80, 443]
        }]
      }
    }
  }
}
