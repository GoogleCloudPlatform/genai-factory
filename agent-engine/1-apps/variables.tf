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
    class_methods          = optional(string)
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

variable "dns_peering_configs" {
  description = "DNS peering configurations for the Agent Engine network."
  type = map(object({
    target_network_name = optional(string)
    target_project_id   = optional(string)
  }))
  default = {
    "." = {}
  }
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

variable "network_attachment_id" {
  description = "The network attachment ID."
  type        = string
  default     = null
}

variable "networking_config" {
  description = "The networking configuration. Each element is either the id of the resource or the key of the map var.vpc_self_links."
  type = object({
    vpc = string
  })
  nullable = false
}

variable "number" {
  description = "The project number where to create the resources."
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "The unique name prefix to be used for all global unique resources."
  type        = string
  nullable    = false
}

variable "project_id" {
  description = "The project ID where to create the resources."
  type        = string
  nullable    = false
}

variable "proxy_config" {
  description = "The proxy configuration."
  type = object({
    ip_address = string
    port       = number
  })
  nullable = false
}

variable "region" {
  type        = string
  description = "The GCP region where to deploy the resources."
  nullable    = false
}

# Expected keys: service-01/gf-ae-0, service-01/iac-rw
variable "service_account_emails" {
  description = "The service account emails. Each element is the email of the service account or the key of the map var.service_accounts."
  type        = map(string)
  nullable    = false
}

variable "source_config" {
  description = "The source file configurations."
  type = object({
    app_path          = optional(string, "./apps/adk")
    entrypoint_module = optional(string, "agent")
    entrypoint_object = optional(string, "agent")
    # path of the requirements.txt file inside the tar.gz archive
    requirements_path = optional(string, "requirements.txt")
  })
  nullable = false
  default  = {}
}
