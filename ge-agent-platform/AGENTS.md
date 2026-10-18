# Gemini Enterprise & Agent Platform (`ge-agent-platform`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `ge-agent-platform` factory provisions an enterprise-ready **Gemini Enterprise** and **Agent Platform** foundation on Google Cloud:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) and optional Shared VPC host project (`0-prereqs/data/projects/host.yaml`).
  - VPC, subnet, Private Service Connect (PSC), Private Google Access, Cloud DNS response policies, and regional PSC endpoints (`0-prereqs/networking.tf`).
  - Stage 1 RW/RO automation service accounts, application service accounts, and Discovery Engine / Vertex AI / IAM v3 / Secret Manager permissions.
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **Gemini Enterprise App & Assistant** ([`1-apps/gemini-enterprise-apps.tf`](./1-apps/gemini-enterprise-apps.tf)): `google_discovery_engine_search_engine` (`INDUSTRY_VERTICAL_GENERIC`, `SOLUTION_TYPE_SEARCH`, `APP_TYPE_INTRANET`), `google_discovery_engine_assistant` (`default_assistant`), and `google_discovery_engine_widget_config`.
  - **Data Stores, SaaS Data Connectors & Location-Level IdP** ([`1-apps/gemini-enterprise-ds.tf`](./1-apps/gemini-enterprise-ds.tf)):
    - Native GCP data stores (`google_discovery_engine_data_store`) with optional GCS/BigQuery `import_documents` jobs.
    - 3rd-party SaaS data connectors (`google_discovery_engine_data_connector.default`, e.g., Jira, Confluence, SharePoint, Outlook, OneDrive, Teams, ServiceNow).
    - Location-level Identity Provider / ACL configuration (`google_discovery_engine_acl_config.default`).
    - Companion `NO_CONTENT` data store (`google_discovery_engine_data_store.companion`) when a single data store is attached.
  - **Agent Registry & Custom MCP Servers** ([`1-apps/agent-registry.tf`](./1-apps/agent-registry.tf)):
    - Service Directory namespace, endpoints, and services backing custom MCP servers (`var.custom_mcp_servers`), patched with `agentregistry.googleapis.com/actionConfig` via `local-exec`.
    - Discovery of `agentregistry-0000...` principal IDs for agents (`var.agents`) and MCP servers (`var.mcp_servers`) via Cloud Asset Inventory (`data.google_cloud_asset_search_all_resources`).
  - **Model Armor & Agent Gateways** ([`1-apps/agent-gateway-model-armor.tf`](./1-apps/agent-gateway-model-armor.tf)):
    - Regional Model Armor templates (`google_model_armor_template.default`) patched with `modalities` and `dataResidencyCompliant` metadata.
    - Agent Gateways (`var.agent_gateways`) enforcing Model Armor policies on target agents and MCP servers.
  - **Unified Access Policies (IAM v3)** ([`1-apps/agent-gateway.tf`](./1-apps/agent-gateway.tf)):
    - `google_iam_access_policy` and `google_iam_Organizations_policy_binding` / project policy bindings governing agent-to-agent and agent-to-MCP access via `principalSet://.../attribute.agent_registry_id/<agentregistry-id>`.

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
  - [`0-prereqs/networking.tf`](./0-prereqs/networking.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/variables.tf`](./1-apps/variables.tf) & [`1-apps/variables-fast.tf`](./1-apps/variables-fast.tf)
  - [`1-apps/gemini-enterprise-apps.tf`](./1-apps/gemini-enterprise-apps.tf)
  - [`1-apps/gemini-enterprise-ds.tf`](./1-apps/gemini-enterprise-ds.tf)
  - [`1-apps/agent-registry.tf`](./1-apps/agent-registry.tf)
  - [`1-apps/agent-gateway.tf`](./1-apps/agent-gateway.tf)
  - [`1-apps/agent-gateway-model-armor.tf`](./1-apps/agent-gateway-model-armor.tf)
  - [`1-apps/outputs.tf`](./1-apps/outputs.tf)
- **Tests** ([`tests/ge_agent_platform/`](../tests/ge_agent_platform)):
  - `0_prereqs`: `simple`, `no_host_prj`
  - `1_apps`: `simple`, `gemini_enterprise`, `iam`, `model_armor`

## Testing & Inventory Regeneration

```shell
# Run all ge-agent-platform tests
uv run pytest tests/ge_agent_platform

# Regenerate 0-prereqs inventories
for t in simple no_host_prj; do
  uv run tools/plan_summary.py ge-agent-platform/0-prereqs \
    tests/ge_agent_platform/0_prereqs/${t}.tfvars \
    > tests/ge_agent_platform/0_prereqs/${t}.yaml
done

# Regenerate 1-apps inventories
for t in simple gemini_enterprise iam model_armor; do
  uv run tools/plan_summary.py ge-agent-platform/1-apps \
    tests/ge_agent_platform/1_apps/${t}.tfvars \
    > tests/ge_agent_platform/1_apps/${t}.yaml
done

# Format regenerated YAML files
uv run yamlfix tests/ge_agent_platform
```

## Factory-Specific Learnings & Gotchas

### 1. Three-Step Initial Deployment & `default_assistant` Import

- Creating a `google_discovery_engine_search_engine` with `APP_TYPE_INTRANET` automatically provisions a `default_assistant` resource on the backend.
- Because the assistant already exists immediately after engine creation, a subsequent `terraform apply` attempting to create `google_discovery_engine_assistant.default` fails with `409 AlreadyExists` unless imported first:
  1. `terraform apply -target=google_discovery_engine_search_engine.default`
  2. `terraform import 'google_discovery_engine_assistant.default["<app_key>"]' projects/<project_id>/locations/<location>/collections/default_collection/engines/<app_id>/assistants/default_assistant`
  3. `terraform apply`

### 2. Decoupled Search Engine `data_store_ids` & Single-Data-Store Companion Workaround

- **Decoupled Attachment (`terraform_data.app_data_stores`):**
  - Do **not** set `data_store_ids` directly on `google_discovery_engine_search_engine.default` (leave `data_store_ids = []` and ignore it in `lifecycle.ignore_changes`).
  - If `data_store_ids` is set on the engine resource, Terraform embeds data store and connector dependencies into the engine's dependency graph, preventing targeted destruction of a connector (`terraform destroy -target='google_discovery_engine_data_connector.default["..."]'`) and causing `400 FAILED_PRECONDITION: DataStore ... is still associated with Engines` when removing a data store or connector.
  - Instead, `terraform_data.app_data_stores` manages engine `dataStoreIds` via a REST `PATCH` (`?updateMask=dataStoreIds`) on create/update and detaches all data stores (`{"dataStoreIds": []}`) via a `when = destroy` provisioner before any underlying data store or connector is deleted.
- **Discovery Engine Single-Data-Store Constraint (`0` or `>= 2`):**
  - The Discovery Engine `UpdateEngine` API rejects `PATCH` requests that set `dataStoreIds` to a list of length `1` (`Error 400: Number of DataStores must be 0 or >= 2`), even though `CreateEngine` accepts a single store.
  - When an app resolves to exactly `1` attached data store, [`1-apps/gemini-enterprise-ds.tf`](./1-apps/gemini-enterprise-ds.tf) automatically provisions a lightweight companion `NO_CONTENT` data store (`google_discovery_engine_data_store.companion`, ID `<app_id>-companion`) and appends it to the engine's `dataStoreIds` payload so the list has length `2`.

### 3. Location-Level Identity Provider (`google_discovery_engine_acl_config.default`)

- Creating any data connector with `acl_enabled = true` in a fresh GCP project fails with `Error 400: IdP must be selected before creating an ACLed Data Connector` unless the location-level `aclConfig` has been configured first.
- Configure `var.gemini_enterprise_iam.idp_type` (`"GSUITE"` for Google Workspace/Cloud Identity or `"THIRD_PARTY"` with `workforce_pool_name` for Workforce Identity Federation) so `google_discovery_engine_acl_config.default` is provisioned before `google_discovery_engine_data_connector.default` (enforced via `depends_on`).

### 4. Third-Party SaaS Data Connectors (`google_discovery_engine_data_connector.default`)

- **OAuth UI Bootstrap & Import Workflow:**
  - Connectors that require interactive OAuth consent in the Cloud Console (such as Jira, Confluence, or SharePoint/M365 delegated flows) are bootstrapped in the UI and imported into Terraform state via:
    `terraform import 'google_discovery_engine_data_connector.default["<key>"]' projects/<project_id>/locations/<location>/collections/<collection_id>`
- **Zero-Diff Idempotency Rules after Import:**
  1. **`lifecycle { ignore_changes = [collection_display_name] }`:** Although `collection_display_name` is required in HCL, the Discovery Engine `GetDataConnector` API does not return it on read, leaving it `null` in state after `terraform import` (`ForceNew`). Ignoring changes prevents replacement after import.
  2. **`params = {}` Default in Variable Type:** For `entities` items in `var.gemini_enterprise_data_connectors`, default `params` to `optional(map(any), {})` (and `json_params = optional(string)`). The Google provider enforces `ExactlyOneOf: [entities.0.params, entities.0.json_params]`; if both are `null`, `terraform plan` fails validation.
  3. **Auto-Appended Entities (`outlook` & `sharepoint`):** On creation, the Discovery Engine backend automatically appends a `root` entity to `ms_graph_outlook_connector` (`outlook`) and a `site` entity to `ms_graph_sharepoint_connector` (`sharepoint`). Because `entities` is `ForceNew`, always include `root` for `outlook` and `site` for `sharepoint` in `var.gemini_enterprise_data_connectors[*].entities`.
  4. **Sequential `terraform import` Guards:** Because `terraform import` evaluates resource references across all keys in `var.gemini_enterprise_data_connectors`, guard cross-resource lookups in `gemini-enterprise-apps.tf` with `contains(keys(google_discovery_engine_data_connector.default), k)` so importing one connector at a time does not fail when other connectors are not yet in state.
  5. **File-or-Inline `params` & `json_params`:** Connector `params` (string) and entity `json_params` (string) support either a path to a JSON file under `1-apps/data/` (detected via `endswith(..., ".json")` and loaded with `file(...)`) or an inline JSON string. Remind users never to use `jsonencode(...)` inside `.tfvars` files (Terraform forbids function calls in `.tfvars`).
  6. **Connector-Specific Validation Rules:**
     - `confluence` entity names must be from `space`, `page`, `whiteboard`, `blog`, `attachment`, `comment` (`blog`, not `blogpost`).
     - `jira` does not accept `auth_type = "OAUTH2"` in `params` (`Connector source with id 'jira' does not have authorization type 'OAUTH2'`).
  7. **Discovery Engine Service Agent Secret Manager Access:** When connectors reference secrets in Secret Manager (`client_secret` resource version path), the Discovery Engine service agent (`service-<project_number>@gcp-sa-discoveryengine.iam.gserviceaccount.com`) requires both `roles/secretmanager.viewer` and `roles/secretmanager.secretAccessor` (configured in `0-prereqs/data/projects/service-01.yaml`).

### 5. Native Unstructured Data Stores (`google_discovery_engine_data_store`)

- Always configure `document_processing_config` (including `default_parsing_config { digital_parsing_config {} }`) directly on the `google_discovery_engine_data_store` resource so unstructured document imports (`import_documents`) work immediately after provisioning.

### 6. Custom MCP Servers, Agent Registry & Model Armor

- **Custom MCP Server Tool Schemas (`var.custom_mcp_servers`):**
  - `tool_schema` accepts either a path to a `.json` file under `1-apps/data/` or an inline JSON string.
  - [`1-apps/agent-registry.tf`](./1-apps/agent-registry.tf) attaches the MCP `actionConfig` metadata to the Service Directory service via a `local-exec` `PATCH` using `agentregistry.googleapis.com/actionConfig`.
- **Model Armor Regional Modalities & Metadata Patch (`var.model_armor_templates`):**
  - [`1-apps/agent-gateway-model-armor.tf`](./1-apps/agent-gateway-model-armor.tf) patches `templateMetadata` (`modalities` and `dataResidencyCompliant`) via REST `PATCH` after template creation.
  - Regional Model Armor endpoints (e.g., `europe-west1`) only support `MODALITY_TEXT` (`["MODALITY_TEXT"]`). Passing `MODALITY_IMAGE` or `MODALITY_AUDIO` in unsupported regions causes `400 INVALID_ARGUMENT`.
- **Stage 0 APIs & Roles (`0-prereqs/data/projects/service-01.yaml`):**
  - Requires `discoveryengine.googleapis.com`, `agentregistry.googleapis.com`, `servicedirectory.googleapis.com`, `cloudasset.googleapis.com`, `modelarmor.googleapis.com`, and `iam.googleapis.com`, plus `roles/discoveryengine.admin`, `roles/iam.accessPolicyAdmin`, `roles/modelarmor.admin`, `roles/servicedirectory.editor`, and `roles/cloudasset.viewer` on the `service-01` RW service account.
