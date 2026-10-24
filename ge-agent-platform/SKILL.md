---
name: ge-agent-platform
description: Actionable runbook for configuring, deploying, customizing, and operating the ge-agent-platform factory (Gemini Enterprise applications and assistants, first-party and third-party SaaS data connectors, location-level IdP/ACL configuration, Agent Registry endpoints/A2A agents/MCP servers, Custom MCP OAuth 2.0 connectors, Egress Agent Gateway with PSC connectivity template, directional Model Armor templates, and IAM v3 Unified Access Policies). Use this skill whenever a user asks to deploy or configure ge-agent-platform, adopt or create Gemini Enterprise apps and assistants, configure SaaS or Custom MCP data connectors, register services in Agent Registry, or write IAM v3 UAP egress rules for Agent Gateway.
---

# Gemini Enterprise Agent Platform — Deployment & Operations Runbook

This skill guides you through configuring, deploying, customizing, and troubleshooting the [`ge-agent-platform`](./README.md) factory: the end-to-end **Gemini Enterprise & Agent Platform** blueprint managing **Gemini Enterprise applications** (`APP_TYPE_INTRANET`) and **assistants**, **first-party and third-party data connectors** (`onedrive`, `sharepoint`, `outlook`, `confluence`, `jira`, etc.), **Agent Registry** endpoints/A2A agents/MCP servers, **Custom MCP data connectors** with Secret Manager **OAuth 2.0**, the **Egress Agent Gateway** (`AGENT_TO_ANYWHERE`) with Shared VPC PSC connectivity template, directional **Model Armor** templates, and **IAM v3 Unified Access Policies (UAPs)** (`iap.googleapis.com/resources.egressViaIAP`).

> [!NOTE]
> For repository contributor workflows (regenerating `plan_summary.py` test inventories and running `pytest`), also consult [`ge-agent-platform/AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Shared Skills Reference (Do Not Duplicate)

This factory relies on the repository's shared skills in [`../.agents/skills/`](../.agents/skills/README.md) for cross-cutting workflows. Always load the relevant shared skill first:

| Workflow Area | Shared Skill | How `ge-agent-platform` Uses It |
| :--- | :--- | :--- |
| **Stage 0 (`0-prereqs`), BYO-VPC, Fabric FAST** | [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) | Deploys Host (`gf-geap-hp-0`) & Service (`gf-geap-0`) projects, Shared VPC, org policy overrides (`disableCustomMcpServerConnector`, `disableAccessPolicyBinding`), and custom roles (`psc_manager`, `discoveryengineUserBusinessAiCodeOnly`). |
| **Discovery Engine Multi-Region vs. Regional Locations** | [`discovery-engine-and-gecx`](../.agents/skills/discovery-engine-and-gecx/SKILL.md) | Explains multi-regional `var.location` (`eu`, `us`, `global`) for Gemini Enterprise vs. regional `var.region` (`europe-west1`) for Agent Gateway and PSC attachments. |
| **Model Armor Templates & Floor Settings** | [`model-armor`](../.agents/skills/model-armor/SKILL.md) | Explains directional Model Armor templates (`user-to-ge`, `ge-to-user`, `agent-gateway-to-external`, `external-to-agent-gateway`), regional modality constraints (`MODALITY_IMAGE` unsupported in `europe-west1`), and floor settings. |
| **Impersonation Quota Fixes & Clean Teardown** | [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md) | Resolves `403 serviceusage.services.use` and cleans up generated `1-apps` files (`providers.tf`, `terraform.auto.tfvars`). |

______________________________________________________________________

## 2. Factory-Specific Resource & Identity Identifiers

When applying the patterns in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md), use these exact `ge-agent-platform` identifiers:

- **Default Resource Name (`var.name` in `1-apps`):** `"geap"`
- **Locations:**
  - `var.location` (default `"eu"`, allowed `"global"`, `"us"`, `"eu"`) — Location of Gemini Enterprise apps, assistants, data connectors, and assistant-bound Model Armor templates (`user-to-ge`, `ge-to-user`).
  - `var.region` (default `"europe-west1"`) — Regional location of the Egress Agent Gateway, PSC Network Attachment, Agent Connectivity Template, default Agent Registry services, and gateway-bound Model Armor templates (`agent-gateway-to-external`, `external-to-agent-gateway`).
- **Stage 0 Project YAML Templates:**
  - Service project (`gf-geap-0`): [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - Host project (`gf-geap-hp-0`): [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
- **Required Organization Policies & Custom Roles in `service-01.yaml`:**
  - Disables `discoveryengine.managed.disableCustomMcpServerConnector` and `iam.managed.disableAccessPolicyBinding`.
  - Creates custom roles `psc_manager` (granted to `service-01/agentgateway` service agent) and `discoveryengineUserBusinessAiCodeOnly` (for Antigravity access).
  - Grants `service-01/iac-rw` delegated `roles/resourcemanager.projectIamAdmin` scoped via IAM condition exclusively to `roles/discoveryengine.agentspaceRestrictedUser` and `discoveryengineUserBusinessAiCodeOnly`.
- **Required Service Agent IAM Bindings:**
  - **Service project (`service-01.yaml`):**
    - `agentgateway` service agent: `$custom_roles:psc_manager`
    - `dep` service agent: `roles/modelarmor.user`, `roles/modelarmor.calloutUser`, `roles/serviceusage.serviceUsageConsumer`
    - `aiplatform` service agent: `roles/modelarmor.user`
    - `discoveryengine` service agent: `roles/secretmanager.secretAccessor`, `roles/secretmanager.viewer`
  - **Host project (`host.yaml`):**
    - `service-01/iac-rw`: `roles/compute.networkUser`, `roles/compute.networkViewer`, `roles/dns.reader`, `roles/networkconnectivity.consumerNetworkAdmin`, `roles/networkconnectivity.regionalEndpointAdmin`
    - `service-01/agentgateway`: `roles/compute.networkUser`, `roles/dns.peer`

______________________________________________________________________

## 3. Configuration Recipes (`1-apps/terraform.tfvars`)

### Recipe A: Create or Adopt Gemini Enterprise Apps, Assistants, IAM & Antigravity Access

Each entry in `var.gemini_enterprise_apps` (keyed by engine/app ID) can either **create** a new Gemini Enterprise app (when `engine` is set) or **adopt** an existing console-created app (when `engine` is omitted):

```hcl
location = "eu"
region   = "europe-west1"

gemini_enterprise_antigravity_principals = [
  "group:developers@example.com",
]

gemini_enterprise_apps = {
  # 1. Existing Console-created app (manages assistant, gateway binding, and IAM only)
  "gemini-enterprise-existing" = {}

  # 2. Terraform-created Gemini Enterprise app
  "gemini-enterprise-finance" = {
    engine = {
      display_name               = "Finance"
      search_tier                = "SEARCH_TIER_ENTERPRISE"
      required_subscription_tier = "SUBSCRIPTION_TIER_SEARCH_AND_ASSISTANT"
      search_add_ons             = ["SEARCH_ADD_ON_LLM"]
    }
    assistant = {
      display_name       = "Finance Assistant"
      web_grounding_type = "WEB_GROUNDING_TYPE_GOOGLE_SEARCH"
      generation_config = {
        default_language   = "en"
        system_instruction = "You are a helpful finance assistant."
      }
      banned_phrases = [
        {
          phrase            = "competitor-secret"
          match_type        = "SIMPLE_STRING_MATCH"
          ignore_diacritics = true
        }
      ]
      model_armor = {
        enable       = true
        failure_mode = "FAIL_CLOSED"
      }
    }
    iam = {
      "roles/discoveryengine.agentspaceUser" = [
        "group:finance-team@example.com",
      ]
    }
  }
}
```

> [!IMPORTANT]
> **Import the `default_assistant` Before Applying:**
> Discovery Engine automatically creates `default_assistant` alongside every Gemini Enterprise app. Before running `terraform apply` for an app in `gemini_enterprise_apps`, import its assistant (or let Terraform create the engine first, then import):
>
> ```shell
> terraform import 'google_discovery_engine_assistant.default["<APP_ID>"]' \
>   "projects/<PROJECT_ID>/locations/<LOCATION>/collections/default_collection/engines/<APP_ID>/assistants/default_assistant"
> ```

### Recipe B: First-Party and Third-Party Data Connectors (`FEDERATED` & `DATA_INGESTION`)

For ACL-enabled connectors in a new project, configure the location-level Identity Provider in `var.gemini_enterprise_iam` (`idp_type = "GSUITE"` or `"THIRD_PARTY"` with `workforce_pool_name`) so `google_discovery_engine_acl_config.default` is provisioned before the connectors:

```hcl
gemini_enterprise_iam = {
  idp_type = "GSUITE"
}

gemini_enterprise_data_connectors = {
  onedrive = {
    data_source             = "onedrive"
    app_ids                 = ["gemini-enterprise-finance"]
    collection_display_name = "OneDrive"
    connector_modes         = ["FEDERATED"]
    action_config           = { create_bap_connection = false }
    bap_config              = { supported_connector_modes = ["ACTIONS"] }
    destination_configs = [
      {
        key          = "url"
        destinations = [{ host = "https://example-my.sharepoint.com/" }]
      }
    ]
    entities = [
      {
        entity_name = "file"
        params      = "specs/onedrive-file.json" # File path or inline JSON string
      }
    ]
  }
}
```

### Recipe C: Registering Endpoints, A2A Agents, and Custom MCP Servers (with OAuth 2.0)

Register services in `var.agent_registry_services` ([`1-apps/agent-registry.tf`](./1-apps/agent-registry.tf)). For `type = "mcp_server"`, listing Gemini Enterprise app IDs in `agent_gateway_app_ids` automatically creates a federated `custom_mcp` data connector per app, routes it through the Egress Agent Gateway, and attaches it to the app:

```hcl
oauth_config = {
  auth_uri        = "https://accounts.google.com/o/oauth2/v2/auth"
  auth_uri_params = "&access_type=offline&prompt=consent"
  client_id       = "projects/my-service-project/secrets/mcp-oauth-client-id/versions/1"
  client_secret   = "projects/my-service-project/secrets/mcp-oauth-client-secret/versions/1"
  scopes          = ["openid", "email", "profile"]
  token_uri       = "https://oauth2.googleapis.com/token"
}

agent_registry_services = {
  weather-api = {
    display_name = "Weather REST API"
    url          = "https://weather.example.com"
    type         = "endpoint"
    access_policy_rules = {
      allow-support-agent = {
        description = "Allow support-agent to call weather-api"
        principals = [
          "principal://agents.global.proj-1234567890.system.id.goog/resources/aiplatform/projects/1234567890/locations/europe-west1/reasoningEngines/support-agent"
        ]
      }
    }
  }

  weather-mcp = {
    display_name          = "Weather MCP Server"
    url                   = "https://weather-mcp.example.com/mcp"
    type                  = "mcp_server"
    protocol              = "JSONRPC"
    content               = "specs/weather-mcp.json"
    agent_gateway_app_ids = ["gemini-enterprise-finance"]
    access_policy_rules = {
      allow-readonly-tools = {
        principals = ["group:finance-team@example.com"]
        condition  = "destination.agent_registry.mcp_server.tool.annotations.read_only_hint == true"
      }
    }
  }
}
```

> [!IMPORTANT]
> **Secret Manager Version Suffix for MCP OAuth 2.0:**
> Always include `/versions/<VERSION>` (e.g., `/versions/1` or `/versions/latest`) on `client_id` and `client_secret` Secret Manager paths in `oauth_config`, and configure `https://vertexaisearch.cloud.google.com/oauth-redirect` as an Authorized Redirect URI on your OAuth 2.0 Client.

### Recipe D: Egress Agent Gateway, Model Armor & Stage-Level IAM v3 Access Policies (`access_policies`)

```hcl
agent_gateway_config = {
  egress = {
    iap = {
      fail_open            = false
      iam_enforcement_mode = null # Set to "DRY_RUN" for audit-only mode
    }
    model_armor_config = {
      enable = true
    }
    networking = {
      access_types = ["PRIVATE"]
      vpc_egress   = "ALL_TRAFFIC"
    }
    registry_locations = ["regional"]
  }
}

access_policies = {
  geap = {
    display_name = "GEAP Egress Access Policy"
    rules = {
      allow-all-registered = {
        description = "Allow all project agents to reach registered services"
        principals  = ["principalSet://agents.global.proj-1234567890.system.id.goog/*"]
        registry    = true
      }
      allow-external-ocr = {
        description = "Allow POST requests to external OCR API"
        principals  = ["group:finance-team@example.com"]
        condition   = "destination.unregistered.host == 'ocr.example.com' && destination.unregistered.method == 'POST'"
      }
    }
  }
}
```

______________________________________________________________________

## 4. Factory-Specific Gotchas & Troubleshooting (`ge-agent-platform`)

### 1. `cannot update agent connectivity template that is referenced by an agent gateway`

- **Cause:** The Network Connectivity API blocks in-place updates to an Agent Connectivity Template (`access_types`, `vpc_egress`, `dns_peering_config`) while an Agent Gateway references it.
- **Fix:** Choose your `agent_gateway_config.egress.networking` settings up front, or detach/taint the Egress Agent Gateway before changing connectivity template attributes.

### 2. Why Companion Data Stores (`<app_id>-companion`) Are Created

- **Cause:** The Discovery Engine `UpdateEngine` API only accepts `0` or `>= 2` linked `dataStoreIds` when updating an existing search engine—passing exactly `1` data store fails with an API error.
- **Behavior:** [`1-apps/gemini-enterprise-ds.tf`](./1-apps/gemini-enterprise-ds.tf) automatically creates an empty `NO_CONTENT` companion data store (`<app_id>-companion`) per app and attaches it alongside your single data store whenever `length(configured_stores) == 1`. Do not delete the companion data store manually.

### 3. Model Armor Direction Separation Between Assistants (`var.location`) and Agent Gateway (`var.region`)

- Assistant Model Armor templates (`user-to-ge`, `ge-to-user`) must reside in `var.location` (`eu`, `us`, `global`), whereas Agent Gateway Model Armor templates (`agent-gateway-to-external`, `external-to-agent-gateway`) must reside in `var.region` (`europe-west1`) and only support `["MODALITY_TEXT"]`. Never bind the same template direction key to both an assistant and the Agent Gateway.
