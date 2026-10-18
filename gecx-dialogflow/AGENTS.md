# Gemini Enterprise for Customer Experience — Dialogflow CX (`gecx-dialogflow`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `gecx-dialogflow` factory deploys a **Dialogflow CX Conversational Agent** backed by Discovery Engine data stores (FAQ CSV and unstructured Knowledge Base JSON) and a private Cloud Run Function webhook:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) and optional Shared VPC host project (`0-prereqs/data/projects/host.yaml`).
  - VPC, subnet, proxy-only subnet (for internal TCP proxy load balancer), Private Google Access, and Cloud DNS response policies (`0-prereqs/networking.tf`).
  - Stage 1 RW/RO automation service accounts, Cloud Functions / Cloud Build service accounts, and Dialogflow / Discovery Engine service agent permissions.
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **Discovery Engine Chat Engine & Data Stores** ([`1-apps/main.tf`](./1-apps/main.tf)): Provisions FAQ (`SOLUTION_TYPE_CHAT`) and unstructured KB data stores backed by GCS ([`1-apps/data/ds-faq/`](./1-apps/data/ds-faq), [`1-apps/data/ds-kb/`](./1-apps/data/ds-kb)) and a `google_discovery_engine_chat_engine` (which creates the underlying Dialogflow CX agent).
  - **Private Cloud Run Function Webhook & Service Directory** ([`1-apps/cloud-functions.tf`](./1-apps/cloud-functions.tf), [`1-apps/on-prem-services.tf`](./1-apps/on-prem-services.tf)): Deploys a 2nd-gen Cloud Function webhook ([`1-apps/data/function/`](./1-apps/data/function)) fronted by an Internal Regional TCP Proxy Load Balancer and registered in Service Directory for private webhook fulfillment.
  - **Agent Import Scripts** ([`1-apps/scripts/`](./1-apps/scripts), [`1-apps/data/agents/`](./1-apps/data/agents)): Helper CLI and scripts generated via [`1-apps/templates/outputs.sh`](./1-apps/templates/outputs.sh) to configure and restore the Dialogflow CX agent package.

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
  - [`0-prereqs/networking.tf`](./0-prereqs/networking.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/main.tf`](./1-apps/main.tf), [`1-apps/cloud-functions.tf`](./1-apps/cloud-functions.tf), [`1-apps/on-prem-services.tf`](./1-apps/on-prem-services.tf), [`1-apps/variables.tf`](./1-apps/variables.tf), [`1-apps/outputs.tf`](./1-apps/outputs.tf)
  - Agent & webhook data/scripts: [`1-apps/data/`](./1-apps/data), [`1-apps/scripts/`](./1-apps/scripts)
- **Tests** ([`tests/gecx_dialogflow/`](../tests/gecx_dialogflow)):
  - `0_prereqs`: `simple`, `no_host_prj`
  - `1_apps`: `simple`

## Testing & Inventory Regeneration

```shell
# Run all gecx-dialogflow tests
uv run pytest tests/gecx_dialogflow

# Regenerate 0-prereqs inventories
for t in simple no_host_prj; do
  uv run tools/plan_summary.py gecx-dialogflow/0-prereqs \
    tests/gecx_dialogflow/0_prereqs/${t}.tfvars \
    > tests/gecx_dialogflow/0_prereqs/${t}.yaml
done

# Regenerate 1-apps inventory
uv run tools/plan_summary.py gecx-dialogflow/1-apps \
  tests/gecx_dialogflow/1_apps/simple.tfvars \
  > tests/gecx_dialogflow/1_apps/simple.yaml

# Format regenerated YAML files
uv run yamlfix tests/gecx_dialogflow
```

## Factory-Specific Learnings & Gotchas

- **Private Webhook Fulfillment via Service Directory & Internal TCP Proxy LB:**
  - Dialogflow CX private webhooks require Service Directory backed by a regional **Internal TCP Proxy Load Balancer** ([`1-apps/on-prem-services.tf`](./1-apps/on-prem-services.tf)) with a `REGIONAL_MANAGED_PROXY` subnet in [`0-prereqs/networking.tf`](./0-prereqs/networking.tf).
- **Dialogflow Service Agent IAM:**
  - Ensure `service-<project_number>@gcp-sa-dialogflow.iam.gserviceaccount.com` is granted `roles/servicedirectory.viewer` and `roles/servicedirectory.pscAuthorizedService` in Stage 0 so Dialogflow CX can invoke the private webhook.
