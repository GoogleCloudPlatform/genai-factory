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
    egress = optional(object({
      iap = optional(object({
        fail_open = optional(bool, true)
        # Null enforces the IAM policies. Set to 'DRY_RUN' otherwise.
        iam_enforcement_mode = optional(string)
        # Only 'V1' (IAM allow policies) is currently supported.
        # See 'Policy model' in the README.
        policy_version = optional(string, "V1")
        timeout        = optional(string, "2s")
      }), {})
      model_armor_config = optional(object({
        authz_hosts = optional(list(string), [])
        enable      = optional(bool, false)
        fail_open   = optional(bool, false)
        timeout     = optional(string, "2s")
      }), {})
      registry_locations = optional(list(string), ["global", "regional"])
    }), {})
  })
  nullable = false
  default  = {}

  validation {
    condition = (
      var.agent_gateway_config.egress.iap.iam_enforcement_mode == null ||
      var.agent_gateway_config.egress.iap.iam_enforcement_mode == "DRY_RUN"
    )
    error_message = "The iam_enforcement_mode must be 'DRY_RUN', or null to enforce the policies."
  }

  validation {
    condition     = var.agent_gateway_config.egress.iap.policy_version == "V1"
    error_message = "Only the 'V1' policy version is supported. 'V2' evaluates IAM Unified Access Policies, which Terraform cannot bind to a project yet, so the 'agent_registry_iam*' bindings would not be enforced."
  }

  validation {
    condition = length(
      var.agent_gateway_config.egress.registry_locations
    ) <= 2
    error_message = "At most two 'registry_locations' can be attached to an Agent Gateway."
  }

  validation {
    condition = alltrue([
      for location in var.agent_gateway_config.egress.registry_locations :
      contains(["eu", "global", "regional", "us"], location)
    ])
    error_message = "Each 'registry_locations' element must be one of 'eu', 'global', 'regional', 'us'."
  }

  validation {
    condition = (
      length(distinct(var.agent_gateway_config.egress.registry_locations))
      == length(var.agent_gateway_config.egress.registry_locations)
    )
    error_message = "The 'registry_locations' elements must be unique."
  }
}

variable "agent_registry_iam" {
  description = "Agent Registry IAM bindings in {ROLE => [MEMBERS]} format."
  type        = map(list(string))
  nullable    = false
  default     = {}
}

variable "agent_registry_iam_bindings" {
  description = "Authoritative Agent Registry IAM bindings in {KEY => {role = ROLE, members = [], condition = {}}} format. Set at most one of the '*_id' attributes to scope the binding to a single registry resource, or none to target the whole registry. Keys are arbitrary."
  type = map(object({
    members       = list(string)
    role          = string
    agent_id      = optional(string)
    endpoint_id   = optional(string)
    mcp_server_id = optional(string)
    condition = optional(object({
      expression  = string
      title       = string
      description = optional(string)
    }))
  }))
  nullable = false
  default  = {}
  validation {
    condition = alltrue([
      for k, v in var.agent_registry_iam_bindings :
      length(compact([v.agent_id, v.endpoint_id, v.mcp_server_id])) <= 1
    ])
    error_message = "Set at most one of 'agent_id', 'endpoint_id', 'mcp_server_id'."
  }
}

variable "agent_registry_iam_bindings_additive" {
  description = "Additive Agent Registry IAM bindings. Set at most one of the '*_id' attributes to scope the binding to a single registry resource, or none to target the whole registry. Keys are arbitrary."
  type = map(object({
    member        = string
    role          = string
    agent_id      = optional(string)
    endpoint_id   = optional(string)
    mcp_server_id = optional(string)
    condition = optional(object({
      expression  = string
      title       = string
      description = optional(string)
    }))
  }))
  nullable = false
  default  = {}
  validation {
    condition = alltrue([
      for k, v in var.agent_registry_iam_bindings_additive :
      length(compact([v.agent_id, v.endpoint_id, v.mcp_server_id])) <= 1
    ])
    error_message = "Set at most one of 'agent_id', 'endpoint_id', 'mcp_server_id'."
  }
}

variable "agent_registry_iam_by_principals" {
  description = "Authoritative Agent Registry IAM bindings in {PRINCIPAL => [ROLES]} format. Principals need to be statically defined to avoid errors. Merged internally with the 'agent_registry_iam' variable."
  type        = map(list(string))
  nullable    = false
  default     = {}
}

variable "agent_registry_services" {
  description = "Custom service endpoints to register in Agent Registry, keyed by service id."
  type = map(object({
    url          = string
    content      = optional(string)
    description  = optional(string)
    display_name = optional(string)
    location     = optional(string, "global")
    protocol     = optional(string, "HTTP_JSON")
    type         = optional(string, "endpoint")
    iam          = optional(map(list(string)), {})
    iam_bindings = optional(map(object({
      members = list(string)
      role    = string
      condition = optional(object({
        expression  = string
        title       = string
        description = optional(string)
      }))
    })), {})
    iam_bindings_additive = optional(map(object({
      member = string
      role   = string
      condition = optional(object({
        expression  = string
        title       = string
        description = optional(string)
      }))
    })), {})
  }))
  nullable = false
  default  = {}
  validation {
    condition = alltrue([
      for k, v in var.agent_registry_services :
      contains(["JSONRPC", "GRPC", "HTTP_JSON"], v.protocol)
    ])
    error_message = "The protocol must be one of 'JSONRPC', 'GRPC', 'HTTP_JSON'."
  }
  validation {
    condition = alltrue([
      for k, v in var.agent_registry_services :
      contains(["agent", "endpoint", "mcp_server"], v.type)
    ])
    error_message = "The type must be one of 'agent', 'endpoint', 'mcp_server'."
  }
  validation {
    condition = alltrue([
      for k, v in var.agent_registry_services :
      v.content != null if v.type != "endpoint"
    ])
    error_message = "The 'content' must be set when 'type' is not 'endpoint'."
  }
  validation {
    condition = alltrue([
      for k, v in var.agent_registry_services :
      v.content == null if v.type == "endpoint"
    ])
    error_message = "The 'content' must not be set when 'type' is 'endpoint'."
  }
}

variable "enable_deletion_protection" {
  description = "Whether deletion protection is enabled."
  type        = bool
  nullable    = false
  default     = true
}

variable "model_armor_template_config" {
  description = "The Model Armor configuration for templates and floor settings."
  type = object({
    enabled          = optional(bool, true)
    enforcement_type = optional(string, "INSPECT_AND_BLOCK")
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
    logging = optional(bool, true)
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
    request_template_id  = optional(string, "agw-request-template")
    response_template_id = optional(string, "agw-response-template")
    # Sensitive Data Protection (DLP)
    sdp = optional(object({
      enabled = optional(string, "ENABLED")
    }), {})
  })
  nullable = false
  default  = {}

  validation {
    condition = contains(
      ["INSPECT_ONLY", "INSPECT_AND_BLOCK"],
      var.model_armor_template_config.enforcement_type
    )
    error_message = "The enforcement_type must be either 'INSPECT_ONLY' or 'INSPECT_AND_BLOCK'."
  }

  validation {
    condition = alltrue([
      contains(
        ["ENABLED", "DISABLED"],
        var.model_armor_template_config.sdp.enabled
      ),
      contains(
        ["ENABLED", "DISABLED"],
        var.model_armor_template_config.malicious_uri.enabled
      ),
      contains(
        ["ENABLED", "DISABLED"],
        var.model_armor_template_config.pi_and_jailbreak.enabled
      )
    ])
    error_message = "The 'enabled' field for sdp, malicious_uri, and pi_and_jailbreak must be either 'ENABLED' or 'DISABLED'."
  }

  validation {
    condition = alltrue([
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_template_config.pi_and_jailbreak.confidence_level
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_template_config.rai_filters.HATE_SPEECH
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_template_config.rai_filters.DANGEROUS
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
      var.model_armor_template_config.rai_filters.HARASSMENT),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_template_config.rai_filters.SEXUALLY_EXPLICIT
      ),
    ])
    error_message = "The confidence_level must be 'LOW_AND_ABOVE', 'MEDIUM_AND_ABOVE', or 'HIGH'."
  }

  validation {
    condition = contains(
      ["INSPECT_ONLY", "INSPECT_AND_BLOCK"],
      var.model_armor_template_config.floor_setting.enforcement_type
    )
    error_message = "The floor_setting enforcement_type must be either 'INSPECT_ONLY' or 'INSPECT_AND_BLOCK'."
  }

  validation {
    condition = alltrue([
      contains(
        ["ENABLED", "DISABLED"],
        var.model_armor_template_config.floor_setting.sdp.enabled
      ),
      contains(
        ["ENABLED", "DISABLED"],
        var.model_armor_template_config.floor_setting.malicious_uri.enabled
      ),
      contains(
        ["ENABLED", "DISABLED"],
        var.model_armor_template_config.floor_setting.pi_and_jailbreak.enabled
      )
    ])
    error_message = "The floor_setting 'enabled' field for sdp, malicious_uri, and pi_and_jailbreak must be either 'ENABLED' or 'DISABLED'."
  }

  validation {
    condition = alltrue([
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_template_config.floor_setting.pi_and_jailbreak.confidence_level
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_template_config.floor_setting.rai_filters.HATE_SPEECH
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_template_config.floor_setting.rai_filters.DANGEROUS
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_template_config.floor_setting.rai_filters.HARASSMENT
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_template_config.floor_setting.rai_filters.SEXUALLY_EXPLICIT
      ),
    ])
    error_message = "The floor_setting confidence_level must be 'LOW_AND_ABOVE', 'MEDIUM_AND_ABOVE', or 'HIGH'."
  }
}

variable "name" {
  description = "The name of the resources."
  type        = string
  nullable    = false
  default     = "geap"
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
