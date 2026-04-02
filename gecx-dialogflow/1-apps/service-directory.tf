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
  # sample output
  #
  # {
  #   service-0-ip-0 = {
  #     ip_address = "192.168.0.1"
  #     port       = 443
  #     service    = "service-0"
  #   }
  #   service-0-ip-1 = {
  #     ip_address = "192.168.0.2"
  #     port       = 443
  #     service    = "service-0"
  #   }
  #   service-1-ip-0 = {
  #     ip_address = "192.168.200.1"
  #     port       = 80
  #     service    = "service-1"
  #   }
  # }
  flattened_endpoints = {
    for item in flatten([
      for service, config in local.service_directory_endpoints_configs : [
        # Grab the index to use as a static identifier
        for index, ip in config.ip_addresses : {
          # Use the index instead of the unknown IP address for the map key
          map_key    = "${service}-ip-${index}"
          ip_address = ip
          port       = config.port
          service    = service
        }
      ]
      ]) : item.map_key => {
      ip_address = item.ip_address
      port       = item.port
      service    = item.service
    }
  }
  service_directory_endpoints_configs = (
    var.cloud_function_config.create
    ? merge(
      var.service_directory_endpoints_configs,
      {
        test-function = {
          ip_addresses = [local.lb_int_ip_address]
          port         = 443
        }
      }
    ) : var.service_directory_endpoints_configs
  )
  service_directory_ports = [
    for service, config in local.service_directory_endpoints_configs
    : config.port
  ]
}

resource "google_service_directory_namespace" "sd_namespace" {
  count        = length(local.service_directory_endpoints_configs) == 0 ? 0 : 1
  namespace_id = var.name
  project      = var.project_config.id
  location     = var.region
}

resource "google_service_directory_service" "sd_services" {
  for_each   = local.service_directory_endpoints_configs
  service_id = each.key
  namespace  = google_service_directory_namespace.sd_namespace[0].id
}

resource "google_service_directory_endpoint" "sd_service_endpoints" {
  for_each    = local.flattened_endpoints
  endpoint_id = "${var.name}-${each.key}"

  # Fixed typo: changed each.value.key to each.value.service
  service = google_service_directory_service.sd_services[each.value.service].id
  address = each.value.ip_address
  port    = each.value.port
}
