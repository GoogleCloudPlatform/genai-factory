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

variable "agent_gateway_config" {
  description = "Agent Gateway configuration including authorization extensions."
  type = object({
    access_path = optional(string, "AGENT_TO_ANYWHERE")
    iap = optional(object({
      fail_open            = optional(bool, true)
      iam_enforcement_mode = optional(string, "DRY_RUN")
      policy_version       = optional(string, "V2")
      timeout              = optional(string, "2s")
    }), {})
    model_armor = optional(object({
      authz_hosts = optional(list(string), [])
      enable      = optional(bool, false)
      fail_open   = optional(bool, true)
      timeout     = optional(string, "2s")
    }), {})
  })
  default = {}
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

variable "model_armor_template_config" {
  description = "The Model Armor configuration for templates and floor settings."
  type = object({
    enabled          = optional(bool, true)
    enforcement_type = optional(string, "INSPECT_AND_BLOCK")
    logging          = optional(bool, true)

    request_template_id  = optional(string, "agw-request-template")
    response_template_id = optional(string, "agw-response-template")

    # Sensitive Data Protection (DLP)
    sdp = optional(object({
      enabled = optional(string, "ENABLED")
    }), {})

    # Malicious URI Filter
    malicious_uri = optional(object({
      enabled = optional(string, "ENABLED")
    }), {})

    # PI and Jailbreak
    pi_and_jailbreak = optional(object({
      confidence_level = optional(string, "HIGH")
      enabled          = optional(string, "ENABLED")
    }), {})

    # Responsible AI (RAI) filters
    rai_filters = optional(object({
      DANGEROUS         = optional(string, "HIGH")
      HARASSMENT        = optional(string, "HIGH")
      HATE_SPEECH       = optional(string, "HIGH")
      SEXUALLY_EXPLICIT = optional(string, "HIGH")
    }), {})

    # Floor setting configuration for Vertex AI
    floor_setting = optional(object({
      enabled          = optional(bool, false)
      enforcement_type = optional(string, "INSPECT_AND_BLOCK")
      logging          = optional(bool, true)

      sdp = optional(object({
        enabled = optional(string, "ENABLED")
      }), {})

      malicious_uri = optional(object({
        enabled = optional(string, "ENABLED")
      }), {})

      pi_and_jailbreak = optional(object({
        confidence_level = optional(string, "HIGH")
        enabled          = optional(string, "ENABLED")
      }), {})

      rai_filters = optional(object({
        DANGEROUS         = optional(string, "HIGH")
        HARASSMENT        = optional(string, "HIGH")
        HATE_SPEECH       = optional(string, "HIGH")
        SEXUALLY_EXPLICIT = optional(string, "HIGH")
      }), {})
    }), {})
  })
  nullable = false
  default  = {}

  validation {
    condition     = contains(["INSPECT_ONLY", "INSPECT_AND_BLOCK"], var.model_armor_template_config.enforcement_type)
    error_message = "The enforcement_type must be either 'INSPECT_ONLY' or 'INSPECT_AND_BLOCK'."
  }

  validation {
    condition = alltrue([
      contains(["ENABLED", "DISABLED"], var.model_armor_template_config.sdp.enabled),
      contains(["ENABLED", "DISABLED"], var.model_armor_template_config.malicious_uri.enabled),
      contains(["ENABLED", "DISABLED"], var.model_armor_template_config.pi_and_jailbreak.enabled)
    ])
    error_message = "The 'enabled' field for sdp, malicious_uri, and pi_and_jailbreak must be either 'ENABLED' or 'DISABLED'."
  }

  validation {
    condition = alltrue([
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.pi_and_jailbreak.confidence_level),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.rai_filters.HATE_SPEECH),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.rai_filters.DANGEROUS),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.rai_filters.HARASSMENT),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.rai_filters.SEXUALLY_EXPLICIT),
    ])
    error_message = "The confidence_level must be 'LOW_AND_ABOVE', 'MEDIUM_AND_ABOVE', or 'HIGH'."
  }

  validation {
    condition     = contains(["INSPECT_ONLY", "INSPECT_AND_BLOCK"], var.model_armor_template_config.floor_setting.enforcement_type)
    error_message = "The floor_setting enforcement_type must be either 'INSPECT_ONLY' or 'INSPECT_AND_BLOCK'."
  }

  validation {
    condition = alltrue([
      contains(["ENABLED", "DISABLED"], var.model_armor_template_config.floor_setting.sdp.enabled),
      contains(["ENABLED", "DISABLED"], var.model_armor_template_config.floor_setting.malicious_uri.enabled),
      contains(["ENABLED", "DISABLED"], var.model_armor_template_config.floor_setting.pi_and_jailbreak.enabled)
    ])
    error_message = "The floor_setting 'enabled' field for sdp, malicious_uri, and pi_and_jailbreak must be either 'ENABLED' or 'DISABLED'."
  }

  validation {
    condition = alltrue([
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.floor_setting.pi_and_jailbreak.confidence_level),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.floor_setting.rai_filters.HATE_SPEECH),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.floor_setting.rai_filters.DANGEROUS),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.floor_setting.rai_filters.HARASSMENT),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_template_config.floor_setting.rai_filters.SEXUALLY_EXPLICIT),
    ])
    error_message = "The floor_setting confidence_level must be 'LOW_AND_ABOVE', 'MEDIUM_AND_ABOVE', or 'HIGH'."
  }
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
