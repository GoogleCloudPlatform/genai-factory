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

variable "agent_engine_config" {
  description = "The agent configuration."
  type = object({
    agent_framework        = optional(string, "google-adk")
    class_methods          = optional(list(any), [])
    enable_adk_telemetry   = optional(bool, true)
    enable_adk_msg_capture = optional(bool, true)
    enable_psc_i           = optional(bool, true)
    max_instances          = optional(number, 5)
    min_instances          = optional(number, 1)
    python_version         = optional(string, "3.13")
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
  description = "The name of the agent."
  type        = string
  nullable    = false
  default     = "agent-0"
}

variable "networking_config" {
  description = "The networking configuration."
  type = object({
    create = optional(bool, true)
    # key is the domain
    dns_peering_configs = optional(map(object({
      # by default, all dns queries go to your VPC.
      target_network_name = optional(string)
      target_project_id   = optional(string)
      })), {
      "." = {}
    })
    # to be set if create = false
    network_attachment_id = optional(string)
    proxy_ip              = optional(string, "10.0.0.100")
    proxy_port            = optional(string, "443")
    subnet = optional(object({
      ip_cidr_range = optional(string, "10.0.0.0/24")
      name          = optional(string, "sub-0")
    }), {})
    subnet_proxy_only = optional(object({
      ip_cidr_range = optional(string, "10.20.0.0/24")
      name          = optional(string, "proxy-only-sub-0")
    }), {})
    vpc_id = optional(string, "net-0")
  })
  nullable = false
  default  = {}
}

variable "prefix" {
  description = "The unique name prefix to be used for all global unique resources."
  type        = string
  nullable    = false
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

variable "source_config" {
  description = "The source file configurations."
  type = object({
    entrypoint_module = optional(string, "agent")
    entrypoint_object = optional(string, "agent")
    # path of the requirements.txt file inside the tar.gz archive
    requirements_path = optional(string, "requirements.txt")
    # name of the generated tar.gz file
    tar_gz_file_name = optional(string, "source.tar.gz")
  })
  nullable = false
  default  = {}
}
