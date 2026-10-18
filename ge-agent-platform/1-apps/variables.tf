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

variable "access_policies" {
  description = "IAM v3 Unified Access Policies (UAPs) and their bindings, keyed by policy ID. Set 'rules' to create a project access policy and bind it, or 'policy_reuse' to bind an existing access policy."
  type = map(object({
    annotations     = optional(map(string))
    bind            = optional(bool, true)
    binding_id      = optional(string)
    display_name    = optional(string)
    policy_reuse    = optional(string)
    target_resource = optional(string, "project")
    binding_condition = optional(object({
      expression  = string
      title       = optional(string)
      description = optional(string)
      location    = optional(string)
    }))
    rules = optional(map(object({
      principals           = list(string)
      agent_id             = optional(string)
      condition            = optional(string)
      condition_service    = optional(string, "iap.googleapis.com")
      description          = optional(string)
      effect               = optional(string, "ALLOW")
      endpoint_id          = optional(string)
      excluded_permissions = optional(list(string), [])
      excluded_principals  = optional(list(string), [])
      location             = optional(string)
      mcp_server_id        = optional(string)
      permissions = optional(
        list(string), ["iap.googleapis.com/resources.egressViaIAP"]
      )
      registry = optional(bool, false)
    })), {})
  }))
  nullable = false
  default  = {}

  validation {
    condition = alltrue(flatten([
      for k, v in var.access_policies : [
        for rk, rv in v.rules : contains(["ALLOW", "DENY"], rv.effect)
      ]
    ]))
    error_message = "Rule 'effect' must be 'ALLOW' or 'DENY'."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.access_policies : [
        for rk, rv in v.rules : (
          (rv.registry ? 1 : 0) +
          length(compact([
            rv.agent_id,
            rv.endpoint_id,
            rv.mcp_server_id,
          ]))
        ) <= 1
      ]
    ]))
    error_message = "Set at most one of 'agent_id', 'endpoint_id', 'mcp_server_id', or 'registry' per rule."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.access_policies : [
        for rk, rv in v.rules :
        length(rv.principals) > 0 && length(rv.permissions) > 0
      ]
    ]))
    error_message = "Each access policy rule must specify at least one principal and one permission."
  }
}

variable "agent_gateway_config" {
  description = "Agent Gateway configuration including VPC connectivity and authorization extensions."
  type = object({
    egress = optional(object({
      iap = optional(object({
        fail_open = optional(bool, true)
        # Null enforces the IAM policies. Set to 'DRY_RUN' otherwise.
        iam_enforcement_mode = optional(string)
        timeout              = optional(string, "2s")
      }), {})
      model_armor_config = optional(object({
        authz_hosts        = optional(list(string), [])
        enable             = optional(bool, false)
        fail_open          = optional(bool, false)
        request_direction  = optional(string, "agent-gateway-to-external")
        response_direction = optional(string, "external-to-agent-gateway")
        timeout            = optional(string, "2s")
      }), {})
      # Settings of the agent connectivity template through which the
      # gateway reaches the VPC. The defaults keep every flow inside
      # the network, which is what a VPC-SC perimeter requires.
      networking = optional(object({
        access_types = optional(list(string), ["PRIVATE"])
        dns_peering_config = optional(object({
          domains = list(string)
          # Defaults to var.networking_config.vpc.
          target_network = optional(string)
        }))
        vpc_egress = optional(string, "ALL_TRAFFIC")
      }), {})
      registry_locations = optional(list(string), ["regional"])
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
    condition = length(
      var.agent_gateway_config.egress.registry_locations
    ) <= 1
    error_message = "At most one 'registry_locations' can be attached to an Agent Gateway."
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

  validation {
    condition = length(setsubtract(
      var.agent_gateway_config.egress.networking.access_types,
      ["PRIVATE", "PUBLIC"]
    )) == 0
    error_message = "Each 'networking.access_types' element must be one of 'PRIVATE', 'PUBLIC'."
  }

  validation {
    condition = contains(
      ["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"],
      var.agent_gateway_config.egress.networking.vpc_egress
    )
    error_message = "The 'networking.vpc_egress' must be either 'ALL_TRAFFIC' or 'PRIVATE_RANGES_ONLY'."
  }

  validation {
    condition = (
      var.agent_gateway_config.egress.networking.dns_peering_config == null
      || length(try(var.agent_gateway_config.egress.networking.dns_peering_config.domains, [])) > 0
    )
    error_message = "Specify at least one domain in 'networking.dns_peering_config.domains'."
  }

  validation {
    condition = (
      !var.agent_gateway_config.egress.model_armor_config.enable || alltrue([
        contains(
          keys(var.model_armor_templates),
          var.agent_gateway_config.egress.model_armor_config.request_direction
        ),
        contains(
          keys(var.model_armor_templates),
          var.agent_gateway_config.egress.model_armor_config.response_direction
        ),
      ])
    )
    error_message = "When Agent Gateway Model Armor is enabled, 'request_direction' and 'response_direction' must exist in 'var.model_armor_templates'."
  }
}

variable "agent_registry_services" {
  description = "Custom service endpoints to register in Agent Registry, keyed by service id."
  type = map(object({
    access_policy_rules = optional(map(object({
      principals           = list(string)
      condition            = optional(string)
      condition_service    = optional(string, "iap.googleapis.com")
      description          = optional(string)
      effect               = optional(string, "ALLOW")
      excluded_permissions = optional(list(string), [])
      excluded_principals  = optional(list(string), [])
      permissions          = optional(list(string), ["iap.googleapis.com/resources.egressViaIAP"])
      policy_id            = optional(string)
    })), {})
    agent_gateway_app_ids = optional(list(string), [])
    content               = optional(string)
    description           = optional(string)
    display_name          = optional(string)
    location              = optional(string)
    oauth_config = optional(object({
      auth_uri = string
      # Plaintext value or Secret Manager version (projects/PROJECT/secrets/SECRET/versions/VERSION)
      client_id       = string
      token_uri       = string
      auth_uri_params = optional(string)
      # Plaintext value or Secret Manager version (projects/PROJECT/secrets/SECRET/versions/VERSION)
      client_secret                = optional(string)
      client_secret_basic_override = optional(bool, true)
      pkce_support_enabled         = optional(bool, true)
      scopes                       = optional(list(string), [])
    }))
    protocol = optional(string, "HTTP_JSON")
    type     = optional(string, "endpoint")
    url      = optional(string)
  }))
  nullable = false
  default  = {}
  validation {
    condition = alltrue(flatten([
      for k, v in var.agent_registry_services : [
        for rk, rv in v.access_policy_rules : contains(["ALLOW", "DENY"], rv.effect)
      ]
    ]))
    error_message = "Each service access_policy_rules 'effect' must be 'ALLOW' or 'DENY'."
  }
  validation {
    condition = alltrue(flatten([
      for k, v in var.agent_registry_services : [
        for rk, rv in v.access_policy_rules :
        length(rv.principals) > 0 && length(rv.permissions) > 0
      ]
    ]))
    error_message = "Each service access_policy_rules entry must specify at least one principal and one permission."
  }
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
  validation {
    condition = alltrue([
      for k, v in var.agent_registry_services :
      v.url != null if v.type != "agent"
    ])
    error_message = "The 'url' must be set when 'type' is not 'agent'."
  }
  validation {
    condition = alltrue([
      for id in keys(var.agent_registry_services) :
      can(regex("^[a-z0-9-]{4,63}$", id))
    ])
    error_message = "Each service id must be 4-63 characters and contain only lowercase letters, digits, and hyphens."
  }
  validation {
    condition = alltrue([
      for s in var.agent_registry_services :
      s.oauth_config == null ? true : can(regex("^https?://[^?#\\s]+$", s.oauth_config.auth_uri))
    ])
    error_message = "Each service oauth_config.auth_uri must be a valid HTTP/HTTPS URL without query parameters or fragments."
  }
  validation {
    condition = alltrue([
      for s in var.agent_registry_services :
      try(s.oauth_config.auth_uri_params, null) == null ? true : can(regex("^(&[^&=]+=[^&]+)*$", s.oauth_config.auth_uri_params))
    ])
    error_message = "Each service oauth_config.auth_uri_params must be in query parameter format: &key1=value1&key2=value2."
  }
  validation {
    condition = alltrue([
      for s in var.agent_registry_services :
      s.oauth_config == null ? true : can(regex("^https?://.*", s.oauth_config.token_uri))
    ])
    error_message = "Each service oauth_config.token_uri must be a valid HTTP/HTTPS URL."
  }
}

variable "enable_deletion_protection" {
  description = "Whether deletion protection is enabled."
  type        = bool
  nullable    = false
  default     = true
}

variable "gemini_enterprise_antigravity_principals" {
  description = "The principals that also get Antigravity. Granted additively at project level with the custom role."
  type        = list(string)
  nullable    = false
  default     = []

  validation {
    condition = alltrue([
      for m in var.gemini_enterprise_antigravity_principals :
      can(regex("^(user|group|serviceAccount|domain):.+$", m))
      || can(regex("^principalSet?://.+$", m))
    ])
    error_message = "Principals must be prefixed (user:, group:, serviceAccount:, domain:) or be a principal:// or principalSet:// identity. allUsers, allAuthenticatedUsers and deleted: are not accepted on a project-wide grant."
  }
}

variable "gemini_enterprise_apps" {
  description = "The Gemini Enterprise apps, keyed by engine id."
  type = map(object({
    assistant = optional(object({
      assistant_id = optional(string, "default_assistant")
      banned_phrases = optional(list(object({
        phrase            = string
        ignore_diacritics = optional(bool)
        match_type        = optional(string)
      })), [])
      description  = optional(string)
      display_name = optional(string, "Default Assistant")
      generation_config = optional(object({
        default_language   = optional(string)
        system_instruction = optional(string)
      }))
      model_armor = optional(object({
        enable                = optional(bool, false)
        failure_mode          = optional(string, "FAIL_CLOSED")
        response_direction    = optional(string, "ge-to-user")
        user_prompt_direction = optional(string, "user-to-ge")
      }), {})
      web_grounding_type = optional(string)
    }), {})
    collection_id = optional(string, "default_collection")
    # Data stores are attached after the fact, so an app starts without any.
    engine = optional(object({
      display_name      = string
      company_name      = optional(string)
      data_store_ids    = optional(list(string), [])
      disable_analytics = optional(bool)
      features          = optional(map(string), {})
      industry_vertical = optional(string, "GENERIC")
      knowledge_graph = optional(object({
        cloud_knowledge_graph_types    = optional(list(string), [])
        enable_cloud_knowledge_graph   = optional(bool, false)
        enable_private_knowledge_graph = optional(bool, false)
        feature_config = optional(object({
          disable_private_kg_auto_complete       = optional(bool)
          disable_private_kg_enrichment          = optional(bool)
          disable_private_kg_query_ui_chips      = optional(bool)
          disable_private_kg_query_understanding = optional(bool)
        }))
      }), {})
      required_subscription_tier = optional(string)
      search_add_ons             = optional(list(string))
      search_tier                = optional(string)
    }))
    iam = optional(map(list(string)), {})
  }))
  nullable = false
  default  = {}

  validation {
    condition = alltrue(flatten([
      for a in var.gemini_enterprise_apps : [
        for members in values(a.iam) : [
          for m in members :
          can(regex("^(user|group|serviceAccount|domain|deleted):.+$", m))
          || can(regex("^principalSet?://.+$", m))
          || contains(["allUsers", "allAuthenticatedUsers"], m)
        ]
      ]
    ]))
    error_message = "Every IAM principal must be prefixed (user:, group:, serviceAccount:, domain:, deleted:), a principal:// or principalSet:// identity, or allUsers / allAuthenticatedUsers."
  }

  validation {
    condition = alltrue(flatten([
      for a in var.gemini_enterprise_apps : [
        for members in values(a.iam) : [
          for m in members : m == trimspace(m)
        ]
      ]
    ]))
    error_message = "IAM principals must not have leading or trailing whitespace."
  }

  validation {
    condition = alltrue(flatten([
      for a in var.gemini_enterprise_apps : [
        for members in values(a.iam) : length(members) > 0
      ]
    ]))
    error_message = "An IAM role with no principals should be removed rather than left empty."
  }

  validation {
    condition = alltrue(flatten([
      for a in var.gemini_enterprise_apps : [
        for bp in a.assistant.banned_phrases :
        bp.match_type == null || contains(["SIMPLE_STRING_MATCH", "WORD_BOUNDARY_STRING_MATCH"], bp.match_type)
      ]
    ]))
    error_message = "The assistant banned_phrases match_type must be either 'SIMPLE_STRING_MATCH' or 'WORD_BOUNDARY_STRING_MATCH'."
  }

  validation {
    condition = alltrue([
      for a in var.gemini_enterprise_apps :
      contains(["FAIL_CLOSED", "FAIL_OPEN"], a.assistant.model_armor.failure_mode)
    ])
    error_message = "The assistant model_armor failure_mode must be either 'FAIL_CLOSED' or 'FAIL_OPEN'."
  }

  # Directions bound to the Agent Gateway are created in the gateway region,
  # so an assistant in var.location cannot share them.
  validation {
    condition = !var.agent_gateway_config.egress.model_armor_config.enable || alltrue(flatten([
      for a in var.gemini_enterprise_apps : [
        for d in compact([
          a.assistant.model_armor.user_prompt_direction,
          a.assistant.model_armor.response_direction,
          ]) : !contains(compact([
            var.agent_gateway_config.egress.model_armor_config.request_direction,
            var.agent_gateway_config.egress.model_armor_config.response_direction,
        ]), d)
      ] if a.assistant.model_armor.enable
    ]))
    error_message = "A Model Armor direction bound to the Agent Gateway cannot also be bound to an assistant: the gateway needs its templates in the gateway region, assistants need them in var.location."
  }
}

variable "gemini_enterprise_data_connectors" {
  description = "The first-party and third-party Gemini Enterprise data connectors, keyed by collection id."
  type = map(object({
    data_source = string
    action_config = optional(object({
      action_params         = optional(map(string), {})
      create_bap_connection = optional(bool)
    }))
    app_ids           = optional(list(string), [])
    auto_run_disabled = optional(bool)
    bap_config = optional(object({
      enabled_actions           = optional(list(string), [])
      supported_connector_modes = optional(list(string))
    }))
    collection_display_name = optional(string)
    connector_modes         = optional(list(string))
    data_source_version     = optional(number)
    destination_configs = optional(list(object({
      destinations = optional(list(object({
        host = optional(string)
        port = optional(number)
      })))
      key    = optional(string)
      params = optional(string)
    })), [])
    entities = optional(list(object({
      entity_name           = optional(string)
      key_property_mappings = optional(map(string))
      params                = optional(string)
    })), [])
    incremental_refresh_interval = optional(string)
    incremental_sync_disabled    = optional(bool)
    json_params                  = optional(string)
    kms_key_name                 = optional(string)
    metadata = optional(object({
      author            = optional(string)
      description       = optional(string)
      note              = optional(string)
      short_description = optional(string)
      title             = optional(string)
    }))
    params            = optional(map(string))
    refresh_interval  = optional(string, "86400s")
    static_ip_enabled = optional(bool, false)
    sync_mode         = optional(string)
    tag               = optional(string)
  }))
  nullable = false
  default  = {}

  validation {
    condition = alltrue(flatten([
      for dc in var.gemini_enterprise_data_connectors : [
        for m in coalesce(dc.connector_modes, []) :
        contains(["DATA_INGESTION", "ACTIONS", "FEDERATED", "EUA", "FEDERATED_AND_EUA"], m)
      ]
    ]))
    error_message = "Each connector_modes value must be one of 'DATA_INGESTION', 'ACTIONS', 'FEDERATED', 'EUA', 'FEDERATED_AND_EUA'."
  }

  validation {
    condition = alltrue([
      for dc in var.gemini_enterprise_data_connectors :
      dc.sync_mode == null || contains(["PERIODIC", "STREAMING", "CONNECTOR_SYNC_MODE_UNSPECIFIED"], dc.sync_mode)
    ])
    error_message = "The sync_mode must be one of 'PERIODIC', 'STREAMING', 'CONNECTOR_SYNC_MODE_UNSPECIFIED'."
  }

  validation {
    condition = alltrue([
      for dc in var.gemini_enterprise_data_connectors :
      !(dc.params != null && dc.json_params != null)
    ])
    error_message = "Only one of 'params' or 'json_params' may be set on a data connector."
  }
}

variable "gemini_enterprise_iam" {
  description = "How app IAM and Discovery Engine identity provider (IdP) configuration are applied."
  type = object({
    # Defaults to projects/${var.project_id}/roles/discoveryengineUserBusinessAiCodeOnly
    antigravity_role    = optional(string)
    authoritative       = optional(bool, true)
    idp_type            = optional(string)
    workforce_pool_name = optional(string)
  })
  nullable = false
  default  = {}

  validation {
    condition = (
      var.gemini_enterprise_iam.antigravity_role == null
      || can(regex("^(organizations|projects)/[^/]+/roles/.+$", var.gemini_enterprise_iam.antigravity_role))
    )
    error_message = "The antigravity_role must be a custom role, as organizations/ORG_ID/roles/NAME or projects/PROJECT_ID/roles/NAME."
  }

  validation {
    condition = (
      var.gemini_enterprise_iam.idp_type == null
      || contains(["GSUITE", "THIRD_PARTY"], var.gemini_enterprise_iam.idp_type)
    )
    error_message = "The idp_type must be either 'GSUITE' or 'THIRD_PARTY'."
  }

  validation {
    condition = (
      var.gemini_enterprise_iam.idp_type != "THIRD_PARTY"
      || var.gemini_enterprise_iam.workforce_pool_name != null
    )
    error_message = "The workforce_pool_name must be set when idp_type is 'THIRD_PARTY'."
  }
}

variable "location" {
  description = "The location of the Gemini Enterprise resources. Components that address the app must match the location of the app itself."
  type        = string
  nullable    = false
  default     = "eu"

  validation {
    condition     = contains(["global", "us", "eu"], var.location)
    error_message = "The location must be 'global', 'us' or 'eu'."
  }
}

variable "model_armor_floor_setting" {
  description = "The Model Armor floor setting configuration for Vertex AI."
  type = object({
    enabled          = optional(bool, false)
    enforcement_type = optional(string, "INSPECT_AND_BLOCK")
    logging          = optional(bool, true)
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
    sdp = optional(object({
      enabled = optional(string, "ENABLED")
    }), {})
  })
  nullable = false
  default  = {}

  validation {
    condition = contains(
      ["INSPECT_ONLY", "INSPECT_AND_BLOCK"],
      var.model_armor_floor_setting.enforcement_type
    )
    error_message = "The floor_setting enforcement_type must be either 'INSPECT_ONLY' or 'INSPECT_AND_BLOCK'."
  }

  validation {
    condition = alltrue([
      contains(
        ["ENABLED", "DISABLED"],
        var.model_armor_floor_setting.sdp.enabled
      ),
      contains(
        ["ENABLED", "DISABLED"],
        var.model_armor_floor_setting.malicious_uri.enabled
      ),
      contains(
        ["ENABLED", "DISABLED"],
        var.model_armor_floor_setting.pi_and_jailbreak.enabled
      )
    ])
    error_message = "The floor_setting 'enabled' field for sdp, malicious_uri, and pi_and_jailbreak must be either 'ENABLED' or 'DISABLED'."
  }

  validation {
    condition = alltrue([
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_floor_setting.pi_and_jailbreak.confidence_level
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_floor_setting.rai_filters.HATE_SPEECH
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_floor_setting.rai_filters.DANGEROUS
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_floor_setting.rai_filters.HARASSMENT
      ),
      contains(
        ["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"],
        var.model_armor_floor_setting.rai_filters.SEXUALLY_EXPLICIT
      ),
    ])
    error_message = "The floor_setting confidence_level must be 'LOW_AND_ABOVE', 'MEDIUM_AND_ABOVE', or 'HIGH'."
  }
}

variable "model_armor_template_prefix" {
  description = "An optional prefix prepended to every Model Armor template id."
  type        = string
  nullable    = false
  default     = ""
}

variable "model_armor_templates" {
  description = "The Model Armor templates, keyed by interaction direction. Only templates referenced by the Agent Gateway or a Gemini Enterprise assistant are created."
  type = map(object({
    custom_llm_response_safety_error_code    = optional(number, 401)
    custom_llm_response_safety_error_message = optional(string, "This is a custom error message for LLM response")
    custom_prompt_safety_error_code          = optional(number, 400)
    custom_prompt_safety_error_message       = optional(string, "This is a custom error message for prompt")
    enforcement_type                         = optional(string, "INSPECT_AND_BLOCK")
    ignore_partial_invocation_failures       = optional(bool, false)
    logging                                  = optional(bool, true)
    malicious_uri = optional(object({
      enabled = optional(string, "ENABLED")
    }), {})
    modalities = optional(list(string), ["MODALITY_TEXT", "MODALITY_IMAGE"])
    pi_and_jailbreak = optional(object({
      confidence_level = optional(string, "MEDIUM_AND_ABOVE")
      enabled          = optional(string, "ENABLED")
    }), {})
    rai_filters = optional(object({
      DANGEROUS         = optional(string, "LOW_AND_ABOVE")
      HARASSMENT        = optional(string, "LOW_AND_ABOVE")
      HATE_SPEECH       = optional(string, "LOW_AND_ABOVE")
      SEXUALLY_EXPLICIT = optional(string, "LOW_AND_ABOVE")
    }), {})
    sdp = optional(object({
      enabled = optional(string, "ENABLED")
    }), {})
  }))
  nullable = false
  default = {
    "user-to-ge" = {}
    "ge-to-user" = {}
    # The agent gateway pair is created in the gateway region rather than in
    # var.location, and a region supports fewer modalities than a multi-region:
    # europe-west1 rejects MODALITY_IMAGE with 'Region europe-west1 does not
    # support the requested capabilities: Image modality'.
    "agent-gateway-to-external" = { modalities = ["MODALITY_TEXT"] }
    "external-to-agent-gateway" = { modalities = ["MODALITY_TEXT"] }
  }

  validation {
    condition = alltrue([
      for t in var.model_armor_templates :
      contains(["INSPECT_ONLY", "INSPECT_AND_BLOCK"], t.enforcement_type)
    ])
    error_message = "The enforcement_type must be either 'INSPECT_ONLY' or 'INSPECT_AND_BLOCK'."
  }

  validation {
    condition = alltrue(flatten([
      for t in var.model_armor_templates : [
        contains(["ENABLED", "DISABLED"], t.sdp.enabled),
        contains(["ENABLED", "DISABLED"], t.malicious_uri.enabled),
        contains(["ENABLED", "DISABLED"], t.pi_and_jailbreak.enabled),
      ]
    ]))
    error_message = "The 'enabled' field for sdp, malicious_uri, and pi_and_jailbreak must be either 'ENABLED' or 'DISABLED'."
  }

  validation {
    condition = alltrue(flatten([
      for t in var.model_armor_templates : [
        contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], t.pi_and_jailbreak.confidence_level),
        contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], t.rai_filters.HATE_SPEECH),
        contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], t.rai_filters.DANGEROUS),
        contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], t.rai_filters.HARASSMENT),
        contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], t.rai_filters.SEXUALLY_EXPLICIT),
      ]
    ]))
    error_message = "The confidence_level must be 'LOW_AND_ABOVE', 'MEDIUM_AND_ABOVE', or 'HIGH'."
  }

  validation {
    condition = alltrue(flatten([
      for t in var.model_armor_templates : [
        for m in t.modalities : contains(["MODALITY_TEXT", "MODALITY_IMAGE"], m)
      ]
    ]))
    error_message = "The modalities must be 'MODALITY_TEXT' or 'MODALITY_IMAGE'."
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

variable "number" {
  description = "The number of the project where to create the resources. Agent Gateways reference their connectivity template by project number."
  type        = string
  nullable    = false
}

variable "oauth_config" {
  description = "Default OAuth 2.0 configuration for custom MCP server data connectors. Can be overridden per service via agent_registry_services[*].oauth_config."
  type = object({
    auth_uri = string
    # Plaintext value or Secret Manager version (projects/PROJECT/secrets/SECRET/versions/VERSION)
    client_id       = string
    token_uri       = string
    auth_uri_params = optional(string)
    # Plaintext value or Secret Manager version (projects/PROJECT/secrets/SECRET/versions/VERSION)
    client_secret                = optional(string)
    client_secret_basic_override = optional(bool, true)
    pkce_support_enabled         = optional(bool, true)
    scopes                       = optional(list(string), [])
  })
  nullable = true
  default  = null

  validation {
    condition = (
      var.oauth_config == null
      ? true
      : can(regex("^https?://[^?#\\s]+$", var.oauth_config.auth_uri))
    )
    error_message = "The oauth_config.auth_uri must be a valid HTTP/HTTPS URL without query parameters or fragments."
  }

  validation {
    condition = (
      try(var.oauth_config.auth_uri_params, null) == null
      ? true
      : can(regex("^(&[^&=]+=[^&]+)*$", var.oauth_config.auth_uri_params))
    )
    error_message = "The oauth_config.auth_uri_params must be in query parameter format: &key1=value1&key2=value2."
  }

  validation {
    condition = (
      var.oauth_config == null
      ? true
      : can(regex("^https?://.*", var.oauth_config.token_uri))
    )
    error_message = "The oauth_config.token_uri must be a valid HTTP/HTTPS URL."
  }
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
