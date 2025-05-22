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

/*
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

variable "project_id" {
  description = "The project id where to create the resources."
  type        = string
  nullable    = false
}

variable "project_number" {
  description = "The project number where to create the resources."
  type        = string
  nullable    = false
}
*/

variable "project_config" {
  description = "The project id where to create the resources."
  type = object({
    project_id     = optional(string, "project_id")
    project_number = optional(string, "project_number")
  })
  nullable = false
  default  = {}
}

variable "networking_config" {
  description = "The networking configuration."
  type = object({
  create      = optional(bool, true)
  vpc_id      = optional(string, "net-0")
  subnets = optional(list(object({
    ip_cidr_range = optional(string, "10.0.0.0/24")
    name          = optional(string, "sub-0")
    region        = optional(string, "europe-west1")
  })))
  subnets_proxy_only = optional(list(object({
    ip_cidr_range = optional(string, "10.20.0.0/24")
    name          = optional(string, "proxy-only-sub-0")
    region        = optional(string, "europe-west1")
  })))
  })
  nullable = false
  default  = {}
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

variable "service_accounts" {
  description = "The pre-created service accounts used by the blueprint."
  type = map(object({
    email     = string
    iam_email = string
    id        = string
  }))
  default = {}
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
  default     = ["internal.example.com"]
}

variable "customer_name" {
  type        = string
  description = "The string used to identify the customer."
  nullable    = false
  default     = "pso"
}
