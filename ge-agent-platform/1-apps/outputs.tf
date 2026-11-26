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

output "access_policy_ids" {
  description = "The IAM v3 Access Policy resource names, keyed by policy id."
  value       = module.agent_gateway_egress.access_policy_ids
}

output "agent_connectivity_template_ids" {
  description = "The ids of the agent connectivity templates through which the gateways reach the VPC."
  value = {
    egress = module.agent_gateway_egress.connectivity_template_id
  }
}

output "agent_gateway_ids" {
  description = "The Agent Gateway ids. Pass them to the agent-runtime factory to govern the traffic of an agent."
  value = {
    egress = module.agent_gateway_egress.id
  }
}

output "agent_registry_service_names" {
  description = "The resource names of the services registered in Agent Registry, keyed by service id."
  value = {
    for id, s in google_agent_registry_service.agent_registry_services
    : id => s.name
  }
}

output "agent_registry_uris" {
  description = "The Agent Registry URIs."
  value       = local.agent_registry_uris
}

output "gemini_enterprise_acl_config_id" {
  description = "Location-level Discovery Engine ACL configuration resource id."
  value       = try(google_discovery_engine_acl_config.default[0].id, null)
}

output "gemini_enterprise_antigravity_principals" {
  description = "The principals holding the Antigravity custom role on the project."
  value       = var.gemini_enterprise_antigravity_principals
}

output "gemini_enterprise_app_iam_principals" {
  description = "Deduplicated project-eligible IAM principals granted roles across any Gemini Enterprise app."
  value       = local.gemini_enterprise_project_members
}

output "gemini_enterprise_app_names" {
  description = "The resource names of the Gemini Enterprise apps Terraform creates, keyed by app key. Apps that already existed are not listed."
  value = {
    for id, e in google_discovery_engine_search_engine.default
    : id => e.name
  }
}

output "gemini_enterprise_assistant_names" {
  description = "The resource names of the managed assistants, keyed by app key."
  value = {
    for id, a in google_discovery_engine_assistant.default
    : id => a.name
  }
}

output "gemini_enterprise_cmek_config_id" {
  description = "Location-level Discovery Engine CMEK configuration resource id."
  value       = try(google_discovery_engine_cmek_config.default[0].id, null)
}

output "gemini_enterprise_data_connector_names" {
  description = "The resource names of the Gemini Enterprise data connectors, keyed by connector id (or service id and app id for MCP connectors)."
  value = merge(
    {
      for id, dc in google_discovery_engine_data_connector.default :
      id => dc.name
    },
    {
      for service_id, s in var.agent_registry_services : service_id => {
        for app_id in toset(coalesce(s.agent_gateway_app_ids, [])) :
        app_id => google_discovery_engine_data_connector.mcp["${service_id}/${app_id}"].name
        if contains(keys(google_discovery_engine_data_connector.mcp), "${service_id}/${app_id}")
      }
      if s.type == "mcp_server" && length(coalesce(s.agent_gateway_app_ids, [])) > 0
    }
  )
}

output "gemini_enterprise_data_store_names" {
  description = "The resource names of the native Discovery Engine data stores, keyed by store key."
  value = {
    for id, ds in google_discovery_engine_data_store.default
    : id => ds.name
  }
  depends_on = [
    google_discovery_engine_schema.default,
  ]
}

output "gemini_enterprise_user_store_id" {
  description = "Location-level Discovery Engine default_user_store resource id."
  value       = try(google_discovery_engine_user_store.default[0].id, null)
}

output "gemini_enterprise_widget_config_names" {
  description = "The resource names of the managed Gemini Enterprise widget configs, keyed by app key."
  value = {
    for id, w in google_discovery_engine_widget_config.default
    : id => w.name
  }
}

output "model_armor_template_names" {
  description = "The resource names of the Model Armor templates, keyed by interaction direction."
  value = {
    for direction, t in google_model_armor_template.default
    : direction => t.name
  }
}

output "policy_binding_ids" {
  description = "The IAM v3 Policy Binding resource names, keyed by policy id."
  value       = module.agent_gateway_egress.policy_binding_ids
}
