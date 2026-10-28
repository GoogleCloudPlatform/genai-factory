---
name: genai-factory-ge-agent-platform
description: Use when deploying or configuring the genai-factory ge-agent-platform blueprint (Gemini Enterprise apps and assistants, SaaS or Custom MCP OAuth 2.0 data connectors, Agent Registry endpoints/A2A agents/MCP servers, Egress Agent Gateway with PSC connectivity template, directional Model Armor templates, and IAM v3 Unified Access Policies).
---

# GenAI Factory — Gemini Enterprise & Agent Platform (`ge-agent-platform`)

## Overview

Deploys the **Gemini Enterprise & Agent Platform** blueprint ([`ge-agent-platform`](./README.md)): Gemini Enterprise intranet apps and assistants, 1P/3P SaaS data connectors, location-level IdP/ACL configuration, **Agent Registry** services, **Custom MCP OAuth 2.0** connectors, the **Egress Agent Gateway** (`AGENT_TO_ANYWHERE`) with Shared VPC PSC connectivity template, directional **Model Armor** templates, and **IAM v3 Unified Access Policies (UAPs)** (`iap.googleapis.com/resources.egressViaIAP`).

## When to Use

- Creating or adopting Gemini Enterprise apps/assistants (`gemini_enterprise_apps`), configuring SaaS connectors (`gemini_enterprise_data_connectors`), or setting location IdP (`gemini_enterprise_iam`).
- Registering endpoints, A2A agents, or Custom MCP servers (`agent_registry_services` + `oauth_config`) and authoring IAM v3 UAP egress rules (`access_policies`).
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO-VPC, and Fabric FAST.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-discovery-engine-and-gecx`](../.agents/skills/genai-factory-discovery-engine-and-gecx/SKILL.md) for multi-regional `var.location` (`eu`/`us`/`global`) vs. regional `var.region` (`europe-west1`).
- **REQUIRED SUB-SKILL:** Load [`genai-factory-model-armor`](../.agents/skills/genai-factory-model-armor/SKILL.md) for directional `model_armor_templates` and regional modality limits.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT` and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-geap-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-geap-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Locations (`1-apps`)** | `var.location` (`eu`/`us`/`global` for GE apps, connectors, `user-to-ge`/`ge-to-user` templates) vs. `var.region` (`europe-west1` for Agent Gateway, PSC attachment, Agent Registry, `*-agent-gateway` templates) |
| **Stage 0 Org Policies & Roles** | Disables `disableCustomMcpServerConnector` & `disableAccessPolicyBinding`; custom roles `psc_manager` (for `agentgateway` SA) & `discoveryengineUserBusinessAiCodeOnly` (for Antigravity) |
| **Service Agent IAM** | `dep` SA: `modelarmor.user`, `modelarmor.calloutUser`, `serviceusage.serviceUsageConsumer`; `discoveryengine` SA: `secretmanager.secretAccessor`/`viewer`; Host `agentgateway` SA: `compute.networkUser`, `dns.peer` |

## Core Patterns

### Create or Adopt Gemini Enterprise Apps & Import `default_assistant`

```hcl
gemini_enterprise_apps = {
  "ge-existing" = {} # Adopts existing console app (manages assistant, gateway & IAM)
  "ge-finance" = {
    engine = {
      display_name               = "Finance"
      search_tier                = "SEARCH_TIER_ENTERPRISE"
      required_subscription_tier = "SUBSCRIPTION_TIER_SEARCH_AND_ASSISTANT"
      search_add_ons             = ["SEARCH_ADD_ON_LLM"]
    }
    assistant = {
      display_name       = "Finance Assistant"
      web_grounding_type = "WEB_GROUNDING_TYPE_GOOGLE_SEARCH"
      model_armor        = { enable = true, failure_mode = "FAIL_CLOSED" }
    }
  }
}
```

Import the auto-created `default_assistant` before managing it:

```shell
terraform import 'google_discovery_engine_assistant.default["<APP_ID>"]' \
  "projects/<PROJECT_ID>/locations/<LOCATION>/collections/default_collection/engines/<APP_ID>/assistants/default_assistant"
```

### Register Custom MCP Server (OAuth 2.0) & Stage-Level IAM v3 UAP

```hcl
oauth_config = {
  auth_uri        = "https://accounts.google.com/o/oauth2/v2/auth"
  auth_uri_params = "&access_type=offline&prompt=consent"
  client_id       = "projects/my-proj/secrets/mcp-client-id/versions/1"
  client_secret   = "projects/my-proj/secrets/mcp-client-secret/versions/1"
  scopes          = ["openid", "email", "profile"]
  token_uri       = "https://oauth2.googleapis.com/token"
}

agent_registry_services = {
  weather-mcp = {
    display_name          = "Weather MCP"
    url                   = "https://weather-mcp.example.com/mcp"
    type                  = "mcp_server"
    protocol              = "JSONRPC"
    content               = "specs/weather-mcp.json"
    agent_gateway_app_ids = ["ge-finance"]
    access_policy_rules = {
      allow-ro = {
        principals = ["group:finance@example.com"]
        condition  = "destination.agent_registry.mcp_server.tool.annotations.read_only_hint == true"
      }
    }
  }
}
```

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| `cannot update agent connectivity template that is referenced by an agent gateway` | Network Connectivity API blocks in-place updates to referenced connectivity templates | Set `agent_gateway_config.egress.networking` up front, or taint/detach the Agent Gateway before changing it. |
| Extra `<app_id>-companion` data store appears in state | Discovery Engine `UpdateEngine` rejects linking exactly `1` data store (`0` or `>= 2` required) | Keep `<app_id>-companion` ([`1-apps/gemini-enterprise-ds.tf`](./1-apps/gemini-enterprise-ds.tf) creates it automatically when `length == 1`). |
| Custom MCP OAuth 2.0 fails or Secret Manager lookup fails | Missing `/versions/<VERSION>` suffix on secret IDs or missing redirect URI | Append `/versions/1` (or `latest`) to `client_id`/`client_secret` and allow `https://vertexaisearch.cloud.google.com/oauth-redirect` on the OAuth client. |
