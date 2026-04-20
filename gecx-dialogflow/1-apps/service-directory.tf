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

module "service_directory" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/service-directory?ref=v55.1.0"
  project_id = var.project_config.id
  location   = var.regions.resources
  name       = coalesce(var.service_directory_configs.namespace_name, var.name)
  services = {
    for k, v in var.service_directory_configs.services
    : k => { endpoints = v.endpoints, metadata = null }
  }
  endpoint_config = {
    for k, v in var.service_directory_configs.endpoints
    : k => { address = v.address, port = v.port, metadata = null }
  }
}

module "dns_service_directory" {
  count = (
    try(var.service_directory_configs.cloud_dns_domain, null) == null
    ? 0 : 1
  )
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns?ref=v55.1.0"
  project_id = var.project_config.id
  name       = replace(var.service_directory_configs.cloud_dns_domain, ".", "-")
  zone_config = {
    domain = "${var.service_directory_configs.cloud_dns_domain}."
    private = {
      client_networks             = [local.vpc_id]
      service_directory_namespace = module.service_directory.id
    }
  }
}
