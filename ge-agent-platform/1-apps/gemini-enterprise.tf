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

# tfdoc:file:description Gemini Enterprise apps, assistants, connectors, and project IAM.

locals {
  gemini_enterprise_antigravity_role = coalesce(
    var.gemini_enterprise_iam.antigravity_role,
    "projects/${var.project_id}/roles/discoveryengineUserBusinessAiCodeOnly"
  )
  gemini_enterprise_restricted_user_role = "roles/discoveryengine.agentspaceRestrictedUser"
}

module "gemini_enterprise" {
  source               = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/geap-gemini-enterprise?ref=lucaprete/geap-gemini-enterprise"
  project_id           = var.project_id
  project_number       = var.number
  location             = var.location
  deletion_protection  = var.enable_deletion_protection
  egress_agent_gateway = "$agent_gateways:egress"

  context = {
    agent_gateways = {
      egress = module.agent_gateway_egress.id
    }
    model_armor_templates = {
      for k, v in google_model_armor_template.default : k => v.name
    }
  }

  idp_config = (
    var.gemini_enterprise_iam.idp_type == null
    ? null
    : {
      idp_type            = var.gemini_enterprise_iam.idp_type
      workforce_pool_name = var.gemini_enterprise_iam.workforce_pool_name
    }
  )

  oauth_config = var.oauth_config

  apps = {
    for app_id, app in var.gemini_enterprise_apps : app_id => {
      assistant = app.assistant == null ? null : {
        assistant_id = app.assistant.assistant_id
        banned_phrases = {
          for bp in app.assistant.banned_phrases : bp.phrase => {
            ignore_diacritics = bp.ignore_diacritics
            match_type        = bp.match_type
            phrase            = bp.phrase
          }
        }
        description       = app.assistant.description
        display_name      = app.assistant.display_name
        generation_config = app.assistant.generation_config
        model_armor_config = !app.assistant.model_armor.enable ? null : {
          failure_mode = app.assistant.model_armor.failure_mode
          response_template = (
            app.assistant.model_armor.response_direction == null
            ? ""
            : "$model_armor_templates:${app.assistant.model_armor.response_direction}"
          )
          user_prompt_template = (
            app.assistant.model_armor.user_prompt_direction == null
            ? ""
            : "$model_armor_templates:${app.assistant.model_armor.user_prompt_direction}"
          )
        }
        web_grounding_type = app.assistant.web_grounding_type
      }
      collection_id = app.collection_id
      engine = app.engine == null ? null : {
        display_name      = app.engine.display_name
        company_name      = app.engine.company_name
        data_store_ids    = app.engine.data_store_ids
        disable_analytics = app.engine.disable_analytics
        features = (
          length(app.engine.features) == 0 ? null : app.engine.features
        )
        industry_vertical = app.engine.industry_vertical
        knowledge_graph = (
          app.engine.knowledge_graph.enable_cloud_knowledge_graph
          || app.engine.knowledge_graph.enable_private_knowledge_graph
          || length(app.engine.knowledge_graph.cloud_knowledge_graph_types) > 0
          || app.engine.knowledge_graph.feature_config != null
          ? app.engine.knowledge_graph
          : null
        )
        required_subscription_tier = app.engine.required_subscription_tier
        search_add_ons             = app.engine.search_add_ons
        search_tier                = app.engine.search_tier
      }
      iam = var.gemini_enterprise_iam.authoritative ? app.iam : {}
      iam_bindings_additive = (
        var.gemini_enterprise_iam.authoritative
        ? {}
        : merge([
          for role, members in app.iam : {
            for member in members :
            "${role} ${member}" => {
              member = member
              role   = role
            }
          }
        ]...)
      )
    }
  }

  data_connectors = {
    for dc_id, dc in var.gemini_enterprise_data_connectors : dc_id => {
      data_source             = dc.data_source
      action_config           = dc.action_config
      app_ids                 = dc.app_ids
      auto_run_disabled       = dc.auto_run_disabled
      bap_config              = dc.bap_config
      collection_display_name = dc.collection_display_name
      connector_modes         = dc.connector_modes
      data_source_version     = dc.data_source_version
      destination_configs = [
        for d in dc.destination_configs : merge(d, {
          params = d.params == null ? null : (
            fileexists("${path.module}/${d.params}")
            ? "${path.module}/${d.params}"
            : d.params
          )
        })
      ]
      entities = [
        for e in dc.entities : merge(e, {
          params = e.params == null ? null : (
            fileexists("${path.module}/${e.params}")
            ? "${path.module}/${e.params}"
            : e.params
          )
        })
      ]
      incremental_refresh_interval = dc.incremental_refresh_interval
      incremental_sync_disabled    = dc.incremental_sync_disabled
      json_params = dc.json_params == null ? null : (
        fileexists("${path.module}/${dc.json_params}")
        ? "${path.module}/${dc.json_params}"
        : dc.json_params
      )
      kms_key           = dc.kms_key_name
      metadata          = dc.metadata
      params            = dc.params
      refresh_interval  = dc.refresh_interval
      static_ip_enabled = dc.static_ip_enabled
      sync_mode         = dc.sync_mode
      tag               = dc.tag
    }
  }

  mcp_connectors = {
    for service_id, s in var.agent_registry_services : service_id => {
      app_ids                  = s.agent_gateway_app_ids
      display_name             = s.display_name
      oauth_config             = s.oauth_config
      url                      = s.url
      use_agent_gateway_egress = true
    }
    if s.type == "mcp_server" && length(coalesce(s.agent_gateway_app_ids, [])) > 0
  }
}

# Project-level companion grant for every principal with a role on an app.
# Always additive, so it never disturbs grants made outside this module.
resource "google_project_iam_member" "agentspace_restricted_user" {
  for_each = module.gemini_enterprise.app_iam_principals

  project = var.project_id
  role    = local.gemini_enterprise_restricted_user_role
  member  = each.value
}

# Grants custom role to access Antigravity (businessaicode.*) at project level.
resource "google_project_iam_member" "antigravity" {
  for_each = toset(var.gemini_enterprise_antigravity_principals)
  project  = var.project_id
  role     = local.gemini_enterprise_antigravity_role
  member   = each.value
}
