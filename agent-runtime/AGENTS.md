# Agent Runtime (`agent-runtime`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `agent-runtime` factory deploys **Vertex AI Agent Engine** runtimes (ADK and A2A agents) in a private VPC environment:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) and optional Shared VPC host project (`0-prereqs/data/projects/host.yaml`).
  - VPC, subnet, Private Service Connect Interface (PSC-I) network attachment, Cloud DNS response policies, and regional PSC endpoints (`0-prereqs/networking.tf`) for multi-regional Vertex AI (`aiplatform.<multi_region>.rep.googleapis.com`) and regional Model Armor (`modelarmor.<region>.rep.googleapis.com`).
  - Stage 1 RW/RO automation service accounts and custom reasoning engine runtime service account (`sa-agent-runtime-01`).
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **Reasoning Engine (`google_vertex_ai_reasoning_engine`)** ([`1-apps/main.tf`](./1-apps/main.tf)): Deploys ADK (`1-apps/apps/adk`) or A2A (`1-apps/apps/adk-a2a`) agents using inline source archives (`inline_source[0].source_archive`) and PSC-I private egress (`psc_interface_config`).
  - **Session & Task Storage**: Native Firestore database (`(default)`) used by the A2A agent to persist conversation sessions and tasks.
  - **Agent Gateways & Model Armor**: Optional integration with `ge-agent-platform` Agent Gateways (`var.agent_gateway_ids`) and Model Armor templates (`var.model_armor_config`).

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
  - [`0-prereqs/networking.tf`](./0-prereqs/networking.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/main.tf`](./1-apps/main.tf), [`1-apps/variables.tf`](./1-apps/variables.tf), [`1-apps/outputs.tf`](./1-apps/outputs.tf)
  - Sample ADK agent: [`1-apps/apps/adk/`](./1-apps/apps/adk)
  - Sample A2A agent: [`1-apps/apps/adk-a2a/`](./1-apps/apps/adk-a2a)
- **Tests** ([`tests/agent_runtime/`](../tests/agent_runtime)):
  - `0_prereqs`: `simple`, `no_host_prj`
  - `1_apps`: `simple`, `a2a`, `agent_gateways`

## Testing & Inventory Regeneration

```shell
# Run all agent-runtime tests
uv run pytest tests/agent_runtime

# Regenerate 0-prereqs inventories
for t in simple no_host_prj; do
  uv run tools/plan_summary.py agent-runtime/0-prereqs \
    tests/agent_runtime/0_prereqs/${t}.tfvars \
    > tests/agent_runtime/0_prereqs/${t}.yaml
done

# Regenerate 1-apps inventories
for t in simple a2a agent_gateways; do
  uv run tools/plan_summary.py agent-runtime/1-apps \
    tests/agent_runtime/1_apps/${t}.tfvars \
    > tests/agent_runtime/1_apps/${t}.yaml
done

# Format regenerated YAML files
uv run yamlfix tests/agent_runtime
```

## Factory-Specific Learnings & Gotchas

- **Inline Source Archive in Terraform Plan (`inline_source[0].source_archive`):**
  - `1-apps/main.tf` packages [`1-apps/apps/adk`](./1-apps/apps/adk) and [`1-apps/apps/adk-a2a`](./1-apps/apps/adk-a2a) into an inline base64-encoded `.tar.gz` archive inside the `google_vertex_ai_reasoning_engine` resource.
  - Whenever **any** file inside `1-apps/apps/adk/` or `1-apps/apps/adk-a2a/` is modified, the base64 tarball in the Terraform plan changes; you **must** regenerate `tests/agent_runtime/1_apps/{simple,a2a,agent_gateways}.yaml` and run `uv run yamlfix`.
- **Reserved `GOOGLE_CLOUD_LOCATION` Env Var on Agent Engine:**
  - Vertex AI Agent Engine reserves the `GOOGLE_CLOUD_LOCATION` environment variable (automatically injecting the regional deployment location, e.g., `europe-west1`) and rejects custom environment variables with that name.
  - To target multi-regional Vertex AI models (`eu` or `us`), pass the model location via `MODEL_LOCATION` in `spec.deployment_spec.env` and set `os.environ["GOOGLE_CLOUD_LOCATION"] = MODEL_LOCATION` inside `agent.py` before initializing ADK agents.
- **PSC-I & Regional Endpoints:**
  - Because the reasoning engine runs with PSC-I private egress, calls to `aiplatform.<multi_region>.rep.googleapis.com` and `modelarmor.<region>.rep.googleapis.com` require the regional PSC endpoints provisioned in [`0-prereqs/networking.tf`](./0-prereqs/networking.tf).
