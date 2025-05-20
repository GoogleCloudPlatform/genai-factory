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

variable "allowed_ip_ranges" {
  description = "The ip ranges that can call the Cloud Run service."
  type        = list(string)
  nullable    = false
  default     = ["0.0.0.0/0"]
}

variable "cloud_run_configs" {
  description = "The Cloud Run configurations."
  type = object({
    containers = optional(map(any), {
      ai = {
        image = "us-docker.pkg.dev/cloudrun/container/hello"
      }
    })
    ingress            = optional(string, "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER")
    max_instance_count = optional(number, 3)
    service_invokers   = optional(list(string), [])
    vpc_access_egress  = optional(string, "ALL_TRAFFIC")
    vpc_access_tags    = optional(list(string), [])
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

variable "ip_address" {
  description = "The optional load balancer IP address. If not specified, the module will create one."
  type        = string
  default     = null
}

variable "name" {
  description = "The name of the resources. This is also the project suffix if a new project is created."
  type        = string
  nullable    = false
  default     = "gf-srun-0"
}


variable "networking_config" {
  description = "The networking configuration."
  type = object({
    create      = optional(bool, true)
    subnet_cidr = optional(string, "10.0.0.0/24")
    subnet_id   = optional(string, "sub-0")
    vpc_id      = optional(string, "net-0")
  })
  nullable = false
  default  = {}
}

variable "proxy_only_networking_config" {
  description = "The proxy-only networking configuration."
  type = object({
    subnet_cidr = optional(string, "10.20.0.0/24")
    subnet_id   = optional(string, "sub-proxy-only-0")
  })
  nullable = false
  default  = {}
}

variable "project_config" {
  description = "The project configuration. Billing id and parent are mandatory if "
  type = object({
    billing_account_id = optional(string)     # if create or control equals true
    control            = optional(bool, true) # control an existing project
    create             = optional(bool, true) # create and control project
    parent             = optional(string)     # if control equals true
  })
  nullable = false
  validation {
    condition = (
      var.project_config.parent == null ||
      can(regex("(organizations|folders)/[0-9]+", var.project_config.parent))
    )
    error_message = "Parent must be of the form folders/folder_id or organizations/organization_id."
  }
}

variable "prefix" {
  description = "The prefix to use for projects and GCS buckets."
  type        = string
  default     = null
}

variable "public_domains" {
  type        = list(string)
  description = "The list of domains connected to the public load balancer."
  nullable    = false
  default     = ["example.com"]
}

variable "region" {
  type        = string
  description = "The GCP region where to deploy the resources."
  nullable    = false
  default     = "europe-west1"
}

variable "expose_external" {
  description = "Whether to expose function externally or not."
  type        = bool
  nullable    = false
  default     = false
}

variable "expose_internal" {
  description = "Whether to expose function internally or not."
  type        = bool
  nullable    = false
  default     = false
}

variable "private_root_domain" {
  type        = string
  description = "The root domain for internal DNS."
  nullable    = false
  default     = "example.com"
}

variable "private_domains" {
  type        = list(string)
  description = "The list of domains connected to the private load balancer."
  nullable    = false
  default     = ["test.example.com"]
}

variable "customer_name" {
  type        = string
  description = "The string used to identify the customer."
  nullable    = false
  default     = "pso"
}
