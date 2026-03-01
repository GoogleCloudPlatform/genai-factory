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

variable "db_configs" {
  description = "The Cloud SQL configurations."
  type = object({
    availability_type = optional(string, "REGIONAL")
    database_version  = optional(string, "POSTGRES_14")
    flags             = optional(map(string), { "cloudsql.iam_authentication" = "on" })
    tier              = optional(string, "db-f1-micro")
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
  description = "The name of the resources. This is also the project suffix if a new project is created."
  type        = string
  nullable    = false
  default     = "gf-pipeline-0"
}

variable "networking_config" {
  description = "The networking configuration."
  type = object({
    create                = optional(bool, true)
    network_attachment_id = optional(string)
    proxy_ip              = optional(string, "10.0.0.100")
    proxy_port            = optional(string, "443")
    vpc_id                = optional(string, "net-0")
    subnet = optional(object({
      ip_cidr_range = optional(string, "10.0.0.0/24")
      name          = optional(string, "sub-0")
    }), {})
    subnet_proxy_only = optional(object({
      ip_cidr_range = optional(string, "10.20.0.0/24")
      name          = optional(string, "proxy-only-sub-0")
      purpose       = optional(string, "REGIONAL_MANAGED_PROXY")
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
  })
  nullable = false
}

variable "region" {
  description = "The region where to create the resources."
  type        = string
  default     = "europe-west1"
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
