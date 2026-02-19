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

# Only used when ILBs are created.
# CA pools can't be recreated in the same project with the same name.
# This can be handy during experimentation
variable "ca_pool_name_suffix" {
  description = "The name suffix of the CA pool used for app ILB certificates."
  type        = string
  nullable    = false
  default     = "ca-pool-0"
}

variable "cloud_run_configs" {
  description = "The Cloud Run configurations."
  type = object({
    containers = optional(map(any), {
      ai = {
        image = "us-docker.pkg.dev/cloudrun/container/hello"
      }
    })
    gpu_zonal_redundancy_disabled = optional(bool, null)
    ingress                       = optional(string, "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER")
    max_instance_count            = optional(number, 3)
    min_instance_count            = optional(number, 1)
    node_selector                 = optional(map(string), null)
    service_invokers              = optional(list(string), [])
    vpc_access_egress             = optional(string, "ALL_TRAFFIC")
    vpc_access_tags               = optional(list(string), [])
  })
  nullable = false
  default  = {}
}

variable "lbs_config" {
  description = "The load balancers configuration."
  type = object({
    external = optional(object({
      enable = optional(bool, true)
      # The optional load balancer IP address.
      # If not specified, the module will create one.
      ip_address        = optional(string)
      domain            = optional(string, "example.com")
      allowed_ip_ranges = optional(list(string), ["0.0.0.0/0"])
    }), {})
    internal = optional(object({
      enable = optional(bool, false)
      # The optional load balancer IP address.
      # If not specified, the module will create one.
      ip_address        = optional(string)
      domain            = optional(string, "example.com")
      allowed_ip_ranges = optional(list(string), ["0.0.0.0/0"])
    }), {})
  })
  nullable = false
  default = {
    external = {}
    internal = {}
  }
}

variable "name" {
  description = "The name of the resources. This is also the project suffix if a new project is created."
  type        = string
  nullable    = false
  default     = "gf-srun-0"
}
