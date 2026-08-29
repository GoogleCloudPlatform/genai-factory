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

variable "enable_model_armor" {
  description = "When true, also create the Model Armor CONTENT_AUTHZ extension and policy. Requires both model_armor_request_template_id and model_armor_response_template_id."
  type        = bool
  default     = false
}

variable "model_armor_request_template_id" {
  description = "Model Armor request-side template ID (regional, in this project + region). Required when enable_model_armor = true."
  type        = string
  default     = null
}

variable "model_armor_response_template_id" {
  description = "Model Armor response-side template ID (regional, in this project + region). Required when enable_model_armor = true."
  type        = string
  default     = null
}

variable "model_armor_authz_hosts" {
  description = "Optional list of Host header values to scope the Model Armor CONTENT_AUTHZ policy to."
  type        = list(string)
  default     = []
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






