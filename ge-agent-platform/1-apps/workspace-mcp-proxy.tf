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

# tfdoc:file:description Cloud Run Workspace MCP internal-domain guardrail proxy.

locals {
  _ws_mcp_cfg = var.workspace_mcp_proxy_config
  _ws_mcp_invokers = distinct(concat(
    [
      "serviceAccount:service-${var.number}@gcp-sa-discoveryengine.iam.gserviceaccount.com",
      "serviceAccount:service-${var.number}@gcp-sa-dep.iam.gserviceaccount.com",
    ],
    local._ws_mcp_cfg.service_invokers
  ))
  workspace_mcp_proxy_registry_entry = local._ws_mcp_cfg.enable ? {
    (local._ws_mcp_cfg.service_id) = {
      access_policy_rules = (
        length(local._ws_mcp_cfg.access_principals) == 0
        ? {}
        : {
          allow-workspace-mcp = {
            condition            = null
            condition_service    = "iap.googleapis.com"
            description          = "Allow governed agents and apps to invoke the internal-domain Workspace MCP proxy."
            effect               = "ALLOW"
            excluded_permissions = []
            excluded_principals  = []
            permissions          = ["iap.googleapis.com/resources.egressViaIAP"]
            policy_id            = null
            principals           = local._ws_mcp_cfg.access_principals
          }
        }
      )
      agent_gateway_app_ids = local._ws_mcp_cfg.app_ids
      content               = "apps/workspace-mcp-proxy/tool_spec.json"
      description           = "Cloud Run MCP proxy enforcing internal corporate recipient domains on Gmail and Google Calendar."
      display_name          = "Workspace Domain-Guardrail MCP Proxy"
      location              = var.region
      oauth_config          = local._ws_mcp_cfg.oauth_config
      protocol              = "JSONRPC"
      type                  = "mcp_server"
      url                   = "${module.workspace_mcp_proxy[0].service.uri}/mcp"
    }
  } : {}
}

module "workspace_mcp_proxy" {
  count               = local._ws_mcp_cfg.enable ? 1 : 0
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2?ref=v60.0.0"
  type                = "SERVICE"
  project_id          = var.project_id
  name                = "${var.name}-ws-mcp-proxy"
  region              = var.region
  deletion_protection = var.enable_deletion_protection
  managed_revision    = false
  containers = {
    proxy = {
      image = local._ws_mcp_cfg.image
      env = {
        ALLOWED_RECIPIENT_DOMAINS           = join(",", local._ws_mcp_cfg.allowed_domains)
        AUTOMATED_SEND_SELF_ONLY            = tostring(local._ws_mcp_cfg.automated_send_self_only)
        ENABLE_AUTOMATED_INTERNAL_SEND_TOOL = tostring(local._ws_mcp_cfg.enable_automated_send_tool)
      }
      ports = {
        http1 = {
          container_port = 8080
          name           = "http1"
        }
      }
    }
  }
  service_account_config = {
    create = local._ws_mcp_cfg.service_account_email == null
    email  = local._ws_mcp_cfg.service_account_email
  }
  iam = {
    "roles/run.invoker" = local._ws_mcp_invokers
  }
  revision = {
    vpc_access = {
      egress  = local._ws_mcp_cfg.vpc_access_egress
      network = var.networking_config.vpc
      subnet  = var.networking_config.subnet
    }
  }
  service_config = {
    gen2_execution_environment = true
    ingress                    = local._ws_mcp_cfg.ingress
    scaling = {
      max_instance_count = local._ws_mcp_cfg.max_instance_count
      min_instance_count = local._ws_mcp_cfg.min_instance_count
    }
  }
  context = {
    networks = var.vpc_self_links
    subnets  = var.subnet_self_links
  }
}
