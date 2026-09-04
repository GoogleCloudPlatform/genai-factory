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

variable "custom_services" {
  description = "List of custom (non-Google) service endpoints to register in Agent Registry."
  type = list(object({
    id           = string
    display_name = string
    url          = string
    description  = optional(string)
  }))
  default = []
}

variable "google_apis" {
  description = "Map of Google API IDs to display names to register in Agent Registry."
  type        = map(string)
  default = {
    "dialogflow"      = "Dialogflow API"
    "discoveryengine" = "Discovery Engine API"
    "modelarmor"      = "Model Armor API"
    "storage"         = "Cloud Storage API"
    "aiplatform"      = "Vertex AI API"
    "logging"         = "Cloud Logging API"
    "monitoring"      = "Cloud Monitoring API"
  }
}

variable "model_armor_config" {
  description = "Model Armor configuration."
  type = object({
    enable               = optional(bool, false)
    request_template_id  = optional(string)
    response_template_id = optional(string)
    authz_hosts          = optional(list(string), [])
  })
  default = {}
}

variable "name" {
  description = "The name of the resources."
  type        = string
  nullable    = false
  default     = "agw-geap"
}

variable "networking_config" {
  description = "The networking configuration. Each element is either the id of the resource or the key of the map var.vpc_self_links."
  type = object({
    subnet = string
    vpc    = string
  })
  nullable = false
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
