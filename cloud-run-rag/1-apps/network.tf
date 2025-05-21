# Copyright 2025 Google LLC
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
    ? module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet_id}"]
    : var.networking_config.subnet_id
  )
  vpc_id = (
    var.networking_config.create
    ? module.vpc[0].id
    : var.networking_config.vpc_id
  )
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc"
  count      = var.networking_config.create ? 1 : 0
  project_id = var.project_id
  name       = var.networking_config.vpc_id
  subnets = [
    {
      ip_cidr_range = var.networking_config.subnet_cidr
      name          = var.networking_config.subnet_id
      region        = var.region
    }
  ]
}

# DNS policies for Google APIs

module "dns_policy_googleapis" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns-response-policy"
  count      = var.networking_config.create ? 1 : 0
  project_id = var.project_id
  name       = "googleapis"
  networks   = { "${var.name}" = local.vpc_id }
  factories_config = {
    rules = "./data/dns-policy-rules.yaml"
  }
}
