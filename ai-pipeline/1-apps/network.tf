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
    ? module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
    : var.networking_config.subnet.name
  )
  vpc_id = (
    var.networking_config.create
    ? module.vpc[0].id
    : var.networking_config.vpc_id
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

# Network Attachment for Private Vertex AI pipeline
resource "google_compute_network_attachment" "pipeline_attachment" {
  name                  = "pipeline-attachment"
  project               = var.project_config.id
  region                = var.region
  connection_preference = "ACCEPT_AUTOMATIC"
  subnetworks           = [module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]]
}

# Secure Web Proxy 

# Internal IP for the Proxy
resource "google_compute_address" "swp_address" {
  name         = "secure-web-proxy"
  region       = var.region
  subnetwork   = module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
  address_type = "INTERNAL"
  project      = var.project_config.id
}

module "secure-web-proxy" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-swp?ref=v51.0.0"
  project_id = var.project_config.id
  region     = var.region
  name       = "secure-web-proxy"
  network    = module.vpc[0].id
  subnetwork = module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
  gateway_config = {
    addresses = [google_compute_address.swp_address.address]
  }
}