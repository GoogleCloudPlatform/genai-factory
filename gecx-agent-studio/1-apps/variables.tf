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

# By default, these values are overridden when you redeploy the app
# by using agentutil. Update the ignore_changes in the google_ces_app resource
# to fully manage and update the resource via terraform.
variable "cx_as_configs" {
  description = "The CX Agent Studio configurations."
  type = object({
    enable_cloud_logging = optional(bool, true)
    speaking_rate        = optional(number, 0)
    supported_languages  = optional(list(string), ["en-US"])
    timezone             = optional(string, "Europe/Rome")
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
  default     = "cx-as-0"
}

variable "prefix" {
  description = "The unique name prefix to be used for all global unique resources."
  type        = string
  nullable    = false
}

variable "project_id" {
  description = "The id of the project where to create the resources."
  type        = string
  nullable    = false
}

variable "region" {
  description = "The GCP region where to deploy the resources."
  type        = string
  nullable    = false
  default     = "europe-west1"
}

variable "region_discovery_engine" {
  description = "The GCP region where to deploy the data store and CX Agent Studio App."
  type        = string
  nullable    = false
  default     = "eu"
  validation {
    condition = (
      var.region_discovery_engine == "eu" || var.region_discovery_engine == "us"
    )
    error_message = "region_discovery_engine should be set either to eu or us."
  }
}
