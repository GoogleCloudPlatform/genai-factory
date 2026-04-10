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

variable "agent_configs" {
  description = "The Dialogflow agent configurations."
  type = object({
    language = optional(string, "en")
    variant  = optional(string, "default")
  })
  nullable = false
  default  = {}
}

variable "bucket_name" {
  description = "The name for all GCS buckets added after the prefix. If not specified, var.name is used instead."
  type        = string
  default     = null
}

# Only used when ILBs are created.
# CA pools can't be recreated in the same project with the same name.
# This can be handy during experimentation
variable "ca_pool_name_suffix" {
  description = "The name suffix of the CA pool used for app ILB certificates."
  type        = string
  nullable    = false
  default     = "ca-pool-0"
}

variable "cloud_function_config" {
  description = "The configuration of an optional Cloud Function to reach via Service Directory."
  type = object({
    bundle_path            = optional(string, "data/function")
    direct_vpc_egress_mode = optional(string, "VPC_EGRESS_ALL_TRAFFIC")
    direct_vpc_egress_tags = optional(list(string), [])
    service_invokers       = optional(list(string), [])
  })
  nullable = false
  default  = {}
}

variable "enable_deletion_protection" {
  description = "Whether deletion protection should be enabled."
  type        = bool
  nullable    = false
  default     = true
}

variable "name" {
  description = "The name of the resources."
  type        = string
  nullable    = false
  default     = "gf-gecx-df-0"
}

variable "networking_config" {
  description = "The networking configuration."
  type = object({
    create = optional(bool, true)
    vpc_id = optional(string, "net-0")
    subnet = optional(object({
      ip_cidr_range = optional(string, "10.0.0.0/24")
      name          = optional(string, "sub-0")
    }), {})
    subnet_proxy_only = optional(object({
      ip_cidr_range = optional(string, "10.20.0.0/24")
      name          = optional(string, "proxy-only-sub-0")
    }), {})
  })
  nullable = false
  default  = {}
}

variable "project_config" {
  description = "The project where to create the resources."
  type = object({
    id     = string
    number = string
    prefix = string
  })
  nullable = false
}

variable "regions" {
  description = "The GCP region where to deploy the Dialogflow agents."
  type = object({
    agent      = optional(string, "europe-west1")
    datastores = optional(string, "eu")
    engine     = optional(string, "eu")
    resources  = optional(string, "europe-west1")
  })
  nullable = false
  default  = {}
}

variable "service_accounts" {
  description = "The pre-created service accounts used by the blueprint."
  type = map(object({
    email     = string
    iam_email = string
    id        = string
  }))
  default = {}
}

# If the Cloud Function is created, its endpoint is automatically created
variable "service_directory_configs" {
  description = "The endpoints to be optionally created in Service Directory."
  type = object({
    cloud_dns_domain            = optional(string)
    create_firewall_policy_rule = optional(bool, true)
    endpoints = optional(map(object({
      address = string
      port    = number
    })), {})
    namespace_name = optional(string)
    services = optional(map(object({
      allowed_ca_certs = optional(list(string))
      endpoints        = list(string)
    })), {})
  })
  nullable = false
  default = {
    cloud_dns_domain            = "example.com"
    create_firewall_policy_rule = true
    endpoints = {
      onprem-ep-one = {
        address = "192.168.0.100"
        port    = 443
      }
    }
    services = {
      onprem = {
        endpoints = ["onprem-ep-one"]
      }
    }
  }
}
