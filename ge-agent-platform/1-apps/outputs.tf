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

output "gemini_enterprise_antigravity_principals" {
  description = "The principals holding the Antigravity custom role on the project."
  value       = var.gemini_enterprise_antigravity_principals
}

output "gemini_enterprise_app_names" {
  description = "The resource names of the Gemini Enterprise apps Terraform creates, keyed by engine id. Apps that already existed are not listed."
  value = {
    for id, e in google_discovery_engine_search_engine.default
    : id => e.name
  }
}

output "gemini_enterprise_assistant_names" {
  description = "The resource names of the managed assistants, keyed by engine id."
  value = {
    for id, a in google_discovery_engine_assistant.default
    : id => a.name
  }
}

output "gemini_enterprise_data_connector_names" {
  description = "The resource names of the Gemini Enterprise data connectors, keyed by connector id (or service id and app id for MCP connectors)."
  value = merge(
    {
      for id, dc in google_discovery_engine_data_connector.default :
      id => dc.name
    },
    {
      for service_id, s in local.all_agent_registry_services : service_id => {
        for app_id in toset(coalesce(s.agent_gateway_app_ids, [])) :
        app_id => google_discovery_engine_data_connector.mcp["${service_id}/${app_id}"].name
        if contains(keys(google_discovery_engine_data_connector.mcp), "${service_id}/${app_id}")
      }
      if s.type == "mcp_server" && length(coalesce(s.agent_gateway_app_ids, [])) > 0
    }
  )
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

output "workspace_mcp_proxy_deploy_commands" {
  description = "Commands to build and deploy the Workspace internal-domain MCP proxy image to Cloud Run."
  value = !var.workspace_mcp_proxy_config.enable ? null : join("\n", [
    "gcloud artifacts repositories create ${var.name}-mcp-repo --repository-format=docker --location=${var.region} --project=${var.project_id} || true",
    "gcloud builds submit ./apps/workspace-mcp-proxy --tag=${var.region}-docker.pkg.dev/${var.project_id}/${var.name}-mcp-repo/workspace-mcp-proxy:latest --project=${var.project_id}",
    "gcloud run services update ${var.name}-ws-mcp-proxy --image=${var.region}-docker.pkg.dev/${var.project_id}/${var.name}-mcp-repo/workspace-mcp-proxy:latest --region=${var.region} --project=${var.project_id}",
  ])
}

output "workspace_mcp_proxy_uri" {
  description = "The Cloud Run URI of the Workspace internal-domain MCP proxy when enabled."
  value       = try("${module.workspace_mcp_proxy[0].service.uri}/mcp", null)
}
