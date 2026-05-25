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
  endpoints_with_lb = merge([
    for namespace_name, namespace_config in var.service_directory_configs : {
      for endpoint_name, endpoint_config in namespace_config.endpoints :
      "${namespace_name}-${endpoint_name}" => {
        address          = endpoint_config.address
        cloud_dns_domain = namespace_config.cloud_dns_domain
        create_lb        = endpoint_config.create_lb
        endpoint         = endpoint_name
        metadata         = endpoint_config.metadata
        namespace        = namespace_name
        port             = endpoint_config.port
      }
      if endpoint_config.create_lb
    }
  ]...)
  iam_principals = {
    for k, v in var.service_accounts
    : k => v.email
  }
}

module "service_directory" {
  for_each   = var.service_directory_configs
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/service-directory?ref=v56.0.0"
  project_id = var.project_id
  location   = var.region
  name       = each.key
  services = {
    for k, v in each.value.services
    : k => {
      endpoints = v.endpoints
      metadata  = v.metadata
    }
  }
  endpoint_config = {
    for k, v in each.value.endpoints
    : k => {
      address = (
        v.create_lb
        ? module.lbs-int-proxy["${each.key}-${k}"].address
        : v.address
      )
      port     = v.port
      metadata = v.metadata
    }
  }
}

module "dns_service_directory" {
  for_each = {
    for k, v in var.service_directory_configs
    : k => v if try(v.cloud_dns_domain, null) != null
  }
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns?ref=v56.0.0"
  project_id = var.project_id
  name       = replace(each.value.cloud_dns_domain, ".", "-")
  zone_config = {
    domain = "${each.value.cloud_dns_domain}."
    private = {
      client_networks             = [var.networking_config.vpc]
      service_directory_namespace = module.service_directory[each.key].id
    }
  }
}

module "lbs-int-proxy" {
  for_each = local.endpoints_with_lb
  source   = "../../../cloud-foundation-fabric/modules/net-lb-proxy-int"
  # source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-proxy-int?ref=v56.0.0"
  name       = each.key
  project_id = var.project_id
  region     = var.region
  port       = each.value.port
  backend_service_config = {
    backends = [
      for zone in toset(var.zones) : {
        group          = zone
        balancing_mode = "CONNECTION"
        max_connections = {
          per_endpoint = 100
        }
    }]
  }
  neg_configs = {
    for zone in toset(var.zones)
    : zone => {
      hybrid = {
        network = "https://www.googleapis.com/compute/v1/${var.networking_config.vpc}"
        zone    = "${var.region}-${zone}"
        endpoints = {
          "0" = {
            ip_address = each.value.address
            port       = each.value.port
          }
        }
      }
    }
  }
  vpc_config = {
    network    = "https://www.googleapis.com/compute/v1/${var.networking_config.vpc}"
    subnetwork = var.networking_config.subnet
  }
  context = {
    iam_principals = local.iam_principals
    networks       = var.vpc_self_links
    subnets        = var.subnet_self_links
  }
}
