# Gemini Enterprise for Customer Experience — Agent Studio (`gecx-agent-studio`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `gecx-agent-studio` factory deploys a **Gemini Enterprise for Customer Experience (CX Agent Studio)** conversational application integrated with an unstructured GCS data store and a private Cloud Run OpenAPI toolset:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) and optional Shared VPC host project (`0-prereqs/data/projects/host.yaml`).
  - VPC, subnet, proxy-only subnet (for internal TCP proxy load balancer), Private Google Access, and Cloud DNS response policies (`0-prereqs/networking.tf`).
  - Stage 1 RW/RO automation service accounts, Cloud Run / Cloud Build service accounts, and Dialogflow / Discovery Engine service agent permissions.
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **Discovery Engine Data Store & GCS Bucket** ([`1-apps/main.tf`](./1-apps/main.tf)): Unstructured data store backed by GCS documents ([`1-apps/data/datastores/`](./1-apps/data/datastores)).
  - **Private Cloud Run Backend & Internal Load Balancer** ([`1-apps/cloud-run.tf`](./1-apps/cloud-run.tf), [`1-apps/cloud-run-lb.tf`](./1-apps/cloud-run-lb.tf), [`1-apps/private-network-access.tf`](./1-apps/private-network-access.tf)): Deploys a private Cloud Run API service ([`1-apps/data/cloud-run/`](./1-apps/data/cloud-run)), exposes it internally via a regional Internal TCP Proxy Load Balancer, and registers it in **Service Directory** so CX Agent Studio can invoke it privately over VPC.
  - **Agent Deployment Scripts** ([`1-apps/scripts/`](./1-apps/scripts), [`1-apps/data/apps/`](./1-apps/data/apps)): Python `agentutil` CLI and helper scripts generated via [`1-apps/templates/outputs.sh`](./1-apps/templates/outputs.sh) to package and import the CX Agent Studio app and toolsets.

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
  - [`0-prereqs/networking.tf`](./0-prereqs/networking.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/main.tf`](./1-apps/main.tf), [`1-apps/cloud-run.tf`](./1-apps/cloud-run.tf), [`1-apps/cloud-run-lb.tf`](./1-apps/cloud-run-lb.tf), [`1-apps/private-network-access.tf`](./1-apps/private-network-access.tf), [`1-apps/variables.tf`](./1-apps/variables.tf), [`1-apps/outputs.tf`](./1-apps/outputs.tf)
  - Agent & toolset data/scripts: [`1-apps/data/`](./1-apps/data), [`1-apps/scripts/`](./1-apps/scripts)
- **Tests** ([`tests/gecx_agent_studio/`](../tests/gecx_agent_studio)):
  - `0_prereqs`: `simple`, `no_host_prj`
  - `1_apps`: `simple`

## Testing & Inventory Regeneration

```shell
# Run all gecx-agent-studio tests
uv run pytest tests/gecx_agent_studio

# Regenerate 0-prereqs inventories
for t in simple no_host_prj; do
  uv run tools/plan_summary.py gecx-agent-studio/0-prereqs \
    tests/gecx_agent_studio/0_prereqs/${t}.tfvars \
    > tests/gecx_agent_studio/0_prereqs/${t}.yaml
done

# Regenerate 1-apps inventory
uv run tools/plan_summary.py gecx-agent-studio/1-apps \
  tests/gecx_agent_studio/1_apps/simple.tfvars \
  > tests/gecx_agent_studio/1_apps/simple.yaml

# Format regenerated YAML files
uv run yamlfix tests/gecx_agent_studio
```

## Factory-Specific Learnings & Gotchas

- **Private Toolset Access via Service Directory & Internal TCP Proxy LB:**
  - Dialogflow / CX Agent Studio reaches private VPC backends through Service Directory PSC integration, which requires an **Internal Regional TCP Proxy Load Balancer** (and a `REGIONAL_MANAGED_PROXY` subnet in `0-prereqs/networking.tf`) fronting the Cloud Run serverless NEG in [`1-apps/cloud-run-lb.tf`](./1-apps/cloud-run-lb.tf) and [`1-apps/private-network-access.tf`](./1-apps/private-network-access.tf).
- **Dialogflow Service Agent IAM:**
  - The Dialogflow service agent (`service-<project_number>@gcp-sa-dialogflow.iam.gserviceaccount.com`) requires `roles/servicedirectory.viewer` and `roles/servicedirectory.pscAuthorizedService` to reach the Service Directory endpoint.
