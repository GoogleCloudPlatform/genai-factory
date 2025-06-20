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

variable "agentspace_configs" {
  description = "The Agentspace configurations."
  type = object({
    target_sites = optional(map(object({
      provided_uri_pattern = string
      exact_match          = optional(bool, false)
      type                 = optional(string, "INCLUDE")
      })), {
      fabric-docs = {
        provided_uri_pattern = "github.com/GoogleCloudPlatform/cloud-foundation-fabric/*"
      }
    })
  })
  nullable = false
  default  = {}
}

variable "name" {
  description = "The name of the resources. This is also the project suffix if a new project is created."
  type        = string
  nullable    = false
  default     = "gf-ai-apps-search-0"
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
  default     = "global"
}

variable "service_accounts" {
  description = "The pre-created service accounts used by the blueprint."
  type = map(object({
    email     = string
    iam_email = string
    id        = string
  }))
  nullable = false
  default  = {}
}
