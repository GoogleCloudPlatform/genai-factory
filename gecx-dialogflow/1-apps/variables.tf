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
  default     = "gecx-df-0"
}

variable "networking_config" {
  description = "The networking configuration. Each element is either the id of the resource or the key of the map var.vpc_self_links."
  type = object({
    subnet = string
    vpc    = string
  })
  nullable = false
}

variable "number" {
  description = "The project number."
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "The name prefix to use for resources with a globally unique name."
  type        = string
  nullable    = false
}

variable "project_id" {
  description = "The id of the project where to create the resources."
  type        = string
  nullable    = false
}

variable "region" {
  type        = string
  description = "The GCP region where to deploy the resources."
  nullable    = false
  default     = "europe-west1"
}

variable "region_discovery_engine" {
  type        = string
  description = "The GCP region where to deploy the Discovery Engine resources."
  nullable    = false
  default     = "eu"
}

# Expected keys: service-01/gecx-df-0, service-01/gecx-df-build-0, service-01/iac-rw
variable "service_account_emails" {
  description = "The service account emails. Each element is the email of the service account or the key of the map var.service_accounts."
  type        = map(string)
  nullable    = false
}

# Expected keys: service-01/gecx-df-0, service-01/gecx-df-build-0, service-01/iac-rw
variable "service_account_ids" {
  description = "The service account ids. Each element is the id of the service account or the key of the map var.service_accounts."
  type        = map(string)
  nullable    = false
}

variable "service_directory_configs" {
  description = "The service to create in Service Directory (key is the namespace name)."
  type = map(object({
    cloud_dns_domain = optional(string)
    endpoints = optional(map(object({
      address   = string
      port      = number
      create_lb = optional(bool, true)
      metadata  = optional(map(string), {})
    })), {})
    services = optional(map(object({
      endpoints        = list(string)
      allowed_ca_certs = optional(list(string))
      metadata         = optional(map(string), {})
    })), {})
  }))
  nullable = false
  default = {
    default = {
      cloud_dns_domain = "example.com"
      endpoints = {
        onprem-01 = {
          address = "192.168.0.100"
          port    = 443
        }
      }
      services = {
        onprem = {
          endpoints = ["onprem-01"]
        }
      }
    }
  }
}

variable "zones" {
  description = "The three zones in the region in use."
  type        = list(string)
  nullable    = false
  default     = ["b", "c", "d"]
}
