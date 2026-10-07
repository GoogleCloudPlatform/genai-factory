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

# tfdoc:file:description Gemini Enterprise apps, assistants, and IAM.

locals {
  gemini_enterprise_antigravity_role = coalesce(
    var.gemini_enterprise_iam.antigravity_role,
    "projects/${var.project_id}/roles/discoveryengineUserBusinessAiCodeOnly"
  )
  gemini_enterprise_app_role_members = merge([
    for key, binding in local.gemini_enterprise_app_roles : {
      for member in binding.members :
      "${key} ${member}" => merge(binding, { member = member })
    }
  ]...)
  gemini_enterprise_app_roles = merge([
    for app_id, app in var.gemini_enterprise_apps : {
      for role, members in app.iam : "${app_id} ${role}" => {
        app_id        = app_id
        collection_id = app.collection_id
        role          = role
        members       = members
      }
    }
  ]...)
  gemini_enterprise_engines = {
    for id, app in var.gemini_enterprise_apps : id => app
    if app.engine != null
  }
  # Anyone holding a role on an app also needs the restricted user role on the
  # project to reach it. Principals that cannot hold a project-level grant
  # (allUsers, allAuthenticatedUsers, deleted:) are skipped.
  gemini_enterprise_project_members = toset([
    for binding in values(local.gemini_enterprise_app_role_members) :
    binding.member
    if !contains(["allUsers", "allAuthenticatedUsers"], binding.member)
    && !startswith(binding.member, "deleted:")
  ])
  gemini_enterprise_restricted_user_role = "roles/discoveryengine.agentspaceRestrictedUser"
}

# A Gemini Enterprise app is a generic search engine with
# app_type set to APP_TYPE_INTRANET.
resource "google_discovery_engine_search_engine" "default" {
  for_each      = local.gemini_enterprise_engines
  project       = var.project_id
  location      = var.location
  collection_id = each.value.collection_id
  engine_id     = each.key
  display_name  = each.value.engine.display_name
  data_store_ids = distinct(concat(
    each.value.engine.data_store_ids,
    [
      for k, dc in local.gemini_enterprise_mcp_data_connectors :
      "${google_discovery_engine_data_connector.mcp[k].collection_id}_mcp_data"
      if dc.app_id == each.key
    ]
  ))
  app_type          = "APP_TYPE_INTRANET"
  industry_vertical = each.value.engine.industry_vertical
  disable_analytics = each.value.engine.disable_analytics
  features          = each.value.engine.features
  deletion_policy   = local.deletion_policy

  search_engine_config {
    search_tier                = each.value.engine.search_tier
    search_add_ons             = each.value.engine.search_add_ons
    required_subscription_tier = each.value.engine.required_subscription_tier
  }

  knowledge_graph_config {
    enable_cloud_knowledge_graph   = each.value.engine.knowledge_graph.enable_cloud_knowledge_graph
    cloud_knowledge_graph_types    = each.value.engine.knowledge_graph.cloud_knowledge_graph_types
    enable_private_knowledge_graph = each.value.engine.knowledge_graph.enable_private_knowledge_graph

    dynamic "feature_config" {
      for_each = (
        each.value.engine.knowledge_graph.feature_config == null
        ? {} : { 1 = 1 }
      )
      content {
        disable_private_kg_query_understanding = each.value.engine.knowledge_graph.feature_config.disable_private_kg_query_understanding
        disable_private_kg_enrichment          = each.value.engine.knowledge_graph.feature_config.disable_private_kg_enrichment
        disable_private_kg_auto_complete       = each.value.engine.knowledge_graph.feature_config.disable_private_kg_auto_complete
        disable_private_kg_query_ui_chips      = each.value.engine.knowledge_graph.feature_config.disable_private_kg_query_ui_chips
      }
    }
  }

  dynamic "common_config" {
    for_each = each.value.engine.company_name == null ? [] : [1]
    content {
      company_name = each.value.engine.company_name
    }
  }
}

# google_discovery_engine_search_engine (provider 8.4.0) does not support
# agentGatewaySetting, so we bind the default egress Agent Gateway via a
# local-exec PATCH.
resource "terraform_data" "app_agent_gateway_patch" {
  for_each = var.gemini_enterprise_apps

  triggers_replace = {
    agent_gateway = module.agent_gateway_egress.id
    collection_id = each.value.collection_id
    engine_id     = each.key
    engine_config = sha256(jsonencode(each.value.engine))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -euo pipefail

      endpoint="https://${var.location == "global" ? "" : "${var.location}-"}discoveryengine.googleapis.com/v1"
      url="$endpoint/projects/${var.number}/locations/${var.location}/collections/${each.value.collection_id}/engines/${each.key}"
      mask="agentGatewaySetting.defaultEgressAgentGateway.name"
      body=$(mktemp)
      trap 'rm -f "$body"' EXIT

      status=$(curl -sS -X PATCH \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -H "X-Goog-User-Project: ${var.project_id}" \
        -d '${jsonencode({
    agentGatewaySetting = {
      defaultEgressAgentGateway = {
        name = module.agent_gateway_egress.id
      }
    }
})}' \
        -o "$body" -w '%%{http_code}' \
        "$url?updateMask=$mask")

      if [[ "$status" != 2* ]]; then
        echo "Agent Gateway engine patch failed for ${each.key} (HTTP $status)" >&2
        cat "$body" >&2
        exit 1
      fi
    EOT
}

depends_on = [
  google_discovery_engine_search_engine.default,
]
}

# Gemini Enterprise creates the assistant together with the app, so this
# adopts an existing resource rather than creating one. Import it before the
# first apply, see README.md.
resource "google_discovery_engine_assistant" "default" {
  for_each = var.gemini_enterprise_apps

  project            = var.project_id
  location           = var.location
  collection_id      = each.value.collection_id
  engine_id          = each.key
  assistant_id       = each.value.assistant.assistant_id
  display_name       = each.value.assistant.display_name
  description        = each.value.assistant.description
  web_grounding_type = each.value.assistant.web_grounding_type

  # The assistant belongs to the app, not to this configuration: Terraform
  # adopts it rather than creating it, so it is never deleted, whatever
  # var.enable_deletion_protection says.
  deletion_policy = "ABANDON"

  dynamic "customer_policy" {
    for_each = (
      each.value.assistant.model_armor.enable || length(each.value.assistant.banned_phrases) > 0
      ? [1] : []
    )
    content {
      dynamic "banned_phrases" {
        for_each = each.value.assistant.banned_phrases
        content {
          phrase            = banned_phrases.value.phrase
          match_type        = banned_phrases.value.match_type
          ignore_diacritics = banned_phrases.value.ignore_diacritics
        }
      }
      dynamic "model_armor_config" {
        for_each = each.value.assistant.model_armor.enable ? [1] : []
        content {
          user_prompt_template = (
            each.value.assistant.model_armor.user_prompt_direction == null
            ? ""
            : google_model_armor_template.default[each.value.assistant.model_armor.user_prompt_direction].name
          )
          response_template = (
            each.value.assistant.model_armor.response_direction == null
            ? ""
            : google_model_armor_template.default[each.value.assistant.model_armor.response_direction].name
          )
          failure_mode = each.value.assistant.model_armor.failure_mode
        }
      }
    }
  }

  dynamic "generation_config" {
    for_each = each.value.assistant.generation_config == null ? [] : [1]
    content {
      default_language = each.value.assistant.generation_config.default_language
      dynamic "system_instruction" {
        for_each = (
          each.value.assistant.generation_config.system_instruction == null
          ? [] : [1]
        )
        content {
          additional_system_instruction = each.value.assistant.generation_config.system_instruction
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition = !each.value.assistant.model_armor.enable || alltrue([
        for d in compact([
          each.value.assistant.model_armor.user_prompt_direction,
          each.value.assistant.model_armor.response_direction,
        ]) : contains(keys(var.model_armor_templates), d)
      ])
      error_message = "App '${each.key}' binds Model Armor directions that are not in var.model_armor_templates."
    }
  }

  # Bind only once the templates carry their final metadata, and only once the
  # app exists when Terraform is the one creating it.
  depends_on = [
    terraform_data.template_metadata_patch,
    google_discovery_engine_search_engine.default,
  ]
}

# App-level IAM. Used when authoritative is false (additive)
resource "google_discovery_engine_search_engine_iam_member" "default" {
  for_each = (
    var.gemini_enterprise_iam.authoritative
    ? {} : local.gemini_enterprise_app_role_members
  )
  project       = var.project_id
  location      = var.location
  collection_id = each.value.collection_id
  engine_id     = each.value.app_id
  role          = each.value.role
  member        = each.value.member
  depends_on = [
    google_discovery_engine_search_engine.default,
  ]
}

# App-level IAM. Used when authoritative is true
resource "google_discovery_engine_search_engine_iam_binding" "default" {
  for_each = (
    var.gemini_enterprise_iam.authoritative
    ? local.gemini_enterprise_app_roles : {}
  )
  project       = var.project_id
  location      = var.location
  collection_id = each.value.collection_id
  engine_id     = each.value.app_id
  role          = each.value.role
  members       = each.value.members
  depends_on = [
    google_discovery_engine_search_engine.default,
  ]
}

# Project-level companion grant for every principal with a role on an app.
# Always additive, so it never disturbs grants made outside this module.
resource "google_project_iam_member" "agentspace_restricted_user" {
  for_each = local.gemini_enterprise_project_members

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
