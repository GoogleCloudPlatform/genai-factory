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

# Only used when ILBs are created.
# CA pools can't be recreated in the same project with the same name.
# This can be handy during experimentation
variable "ca_pool_name_suffix" {
  description = "The name suffix of the CA pool used for app ILB certificates (if any)."
  type        = string
  nullable    = false
  default     = "ca-pool-0"
}

variable "cloud_run_configs" {
  description = "The Cloud Run configurations."
  type = object({
    containers = optional(map(any), {
      ai = {
        image = "us-docker.pkg.dev/cloudrun/container/hello"
      }
    })
    gpu_zonal_redundancy_disabled = optional(bool, null)
    ingress                       = optional(string, "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER")
    max_instance_count            = optional(number, 3)
    min_instance_count            = optional(number, 1)
    node_selector                 = optional(map(string), null)
    service_invokers              = optional(list(string), [])
    vpc_access_egress             = optional(string, "ALL_TRAFFIC")
    vpc_access_tags               = optional(list(string), [])
  })
  nullable = false
  default  = {}
}

variable "enable_deletion_protection" {
  description = "Whether deletion protection is enabled."
  type        = bool
  nullable    = false
  default     = true
}

variable "lbs_configs" {
  description = "The load balancers configurations."
  type = object({
    external = optional(object({
      enable = optional(bool, true)
      # The optional load balancer IP address.
      # If not specified, the module will create one.
      ip_address        = optional(string)
      domain            = optional(string, "example.com")
      allowed_ip_ranges = optional(list(string), ["0.0.0.0/0"])
    }), {})
    internal = optional(object({
      enable = optional(bool, false)
      # The optional load balancer IP address.
      # If not specified, the module will create one.
      ip_address        = optional(string)
      domain            = optional(string, "example.com")
      allowed_ip_ranges = optional(list(string), ["0.0.0.0/0"])
    }), {})
  })
  nullable = false
  default = {
    external = {}
    internal = {}
  }
}

variable "model_armor_floorsetting_config" {
  description = "The default model armor configuration for Vertex AI."
  type = object({
    enabled          = optional(bool, true)
    enforcement_type = optional(string, "INSPECT_AND_BLOCK")
    logging          = optional(bool, true)

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
      enabled          = optional(string, "ENABLED")
      confidence_level = optional(string, "HIGH")
    }), {})

    # Responsible AI (RAI) filters
    rai_filters = optional(object({
      HATE_SPEECH       = optional(string, "HIGH")
      DANGEROUS         = optional(string, "HIGH")
      HARASSMENT        = optional(string, "HIGH")
      SEXUALLY_EXPLICIT = optional(string, "HIGH")
    }), {})
  })
  nullable = false
  default  = {}

  validation {
    condition     = contains(["INSPECT_ONLY", "INSPECT_AND_BLOCK"], var.model_armor_floorsetting_config.enforcement_type)
    error_message = "The enforcement_type must be either 'INSPECT_ONLY' or 'INSPECT_AND_BLOCK'."
  }

  validation {
    condition = alltrue([
      contains(["ENABLED", "DISABLED"], var.model_armor_floorsetting_config.sdp.enabled),
      contains(["ENABLED", "DISABLED"], var.model_armor_floorsetting_config.malicious_uri.enabled),
      contains(["ENABLED", "DISABLED"], var.model_armor_floorsetting_config.pi_and_jailbreak.enabled)
    ])
    error_message = "The 'enabled' field for sdp, malicious_uri, and pi_and_jailbreak must be either 'ENABLED' or 'DISABLED'."
  }

  validation {
    condition = alltrue([
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_floorsetting_config.pi_and_jailbreak.confidence_level),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_floorsetting_config.rai_filters.HATE_SPEECH),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_floorsetting_config.rai_filters.DANGEROUS),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_floorsetting_config.rai_filters.HARASSMENT),
      contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_floorsetting_config.rai_filters.SEXUALLY_EXPLICIT),
    ])
    error_message = "The confidence_level must be 'LOW_AND_ABOVE', 'MEDIUM_AND_ABOVE', or 'HIGH'."
  }
}

variable "model_armor_template_config" {
  description = "The model armor configuration."
  type = object({
    enabled          = optional(bool, true)
    enforcement_type = optional(string, "INSPECT_AND_BLOCK")
    logging          = optional(bool, true)

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
      enabled          = optional(string, "ENABLED")
      confidence_level = optional(string, "HIGH")
    }), {})

    # Responsible AI (RAI) filters
    rai_filters = optional(object({
      HATE_SPEECH       = optional(string, "HIGH")
      DANGEROUS         = optional(string, "HIGH")
      HARASSMENT        = optional(string, "HIGH")
      SEXUALLY_EXPLICIT = optional(string, "HIGH")
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
}

variable "name" {
  description = "The name of the resources."
  type        = string
  nullable    = false
  default     = "gf-srun-0"
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
  type        = string
  description = "The GCP region where to deploy the resources."
  nullable    = false
}

# Expected keys: service-01/iac-rw, service-01/crun-0, service-01/crun-build-0
variable "service_account_emails" {
  description = "The service account emails. Each element is the email or the key of the map var.service_accounts."
  type        = map(string)
  nullable    = false
}

# Expected keys: service-01/iac-rw, service-01/crun-0, service-01/crun-build-0
variable "service_account_ids" {
  description = "The service account ids. Each element is the id or the key of the map var.service_accounts."
  type        = map(string)
  nullable    = false
}
