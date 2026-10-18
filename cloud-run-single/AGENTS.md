# Single Cloud Run GenAI Application (`cloud-run-single`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `cloud-run-single` factory is the reference blueprint for deploying a single containerized **GenAI application or MCP server on Cloud Run** with optional GPU acceleration, Model Armor prompt/response sanitization, and external/internal Application Load Balancing:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) and optional Shared VPC host project (`0-prereqs/data/projects/host.yaml`).
  - VPC, subnet, Private Google Access, Cloud DNS response policies, and regional PSC endpoints (`0-prereqs/networking.tf`) for multi-regional Vertex AI (`aiplatform.<multi_region>.rep.googleapis.com`) and regional Model Armor (`modelarmor.<region>.rep.googleapis.com`).
  - Stage 1 RW/RO automation service accounts and Cloud Run / Cloud Build service accounts.
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **Cloud Run Service & Artifact Registry** ([`1-apps/main.tf`](./1-apps/main.tf)): Runs the application container with Direct VPC egress (`PRIVATE_RANGES_ONLY`), optional NVIDIA L4 GPU (`var.cloud_run_Config.gpu`), and optional GCS volume mounts.
  - **Model Armor** ([`1-apps/model-armor.tf`](./1-apps/model-armor.tf)): Regional Model Armor template (`google_model_armor_template`) for prompt and response sanitization.
  - **Application Load Balancer & Cloud Armor** ([`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), [`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/lb-int-cert.tf`](./1-apps/lb-int-cert.tf)): External or internal HTTPS load balancer with Cloud Armor WAF policy.
  - **Sample Applications** ([`1-apps/apps/`](./1-apps/apps)):
    - [`1-apps/apps/chat/`](./1-apps/apps/chat): FastAPI + `google-genai` chat app with optional Model Armor sanitization.
    - [`1-apps/apps/adk/`](./1-apps/apps/adk): Google ADK agent exposed via FastAPI.
    - [`1-apps/apps/adk-a2a/`](./1-apps/apps/adk-a2a): ADK Agent-to-Agent (A2A) server backed by Firestore.
    - [`1-apps/apps/gemma/`](./1-apps/apps/gemma): Self-hosted Gemma model running on Cloud Run GPU (vLLM / Ollama).
    - [`1-apps/apps/mcp-server/`](./1-apps/apps/mcp-server): Sample FastMCP server deployable on Cloud Run.

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
  - [`0-prereqs/networking.tf`](./0-prereqs/networking.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/main.tf`](./1-apps/main.tf), [`1-apps/model-armor.tf`](./1-apps/model-armor.tf), [`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), [`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/variables.tf`](./1-apps/variables.tf), [`1-apps/outputs.tf`](./1-apps/outputs.tf)
  - Sample applications: [`1-apps/apps/{chat,adk,adk-a2a,gemma,mcp-server}`](./1-apps/apps)
- **Tests** ([`tests/cloud_run_single/`](../tests/cloud_run_single)):
  - `0_prereqs`: `simple`, `no_host_prj`
  - `1_apps`: `simple`

## Testing & Inventory Regeneration

```shell
# Run all cloud-run-single tests
uv run pytest tests/cloud_run_single

# Regenerate 0-prereqs inventories
for t in simple no_host_prj; do
  uv run tools/plan_summary.py cloud-run-single/0-prereqs \
    tests/cloud_run_single/0_prereqs/${t}.tfvars \
    > tests/cloud_run_single/0_prereqs/${t}.yaml
done

# Regenerate 1-apps inventory
uv run tools/plan_summary.py cloud-run-single/1-apps \
  tests/cloud_run_single/1_apps/simple.tfvars \
  > tests/cloud_run_single/1_apps/simple.yaml

# Format regenerated YAML files
uv run yamlfix tests/cloud_run_single
```

## Factory-Specific Learnings & Gotchas

- **Regional Model Armor vs. Multi-Regional Vertex AI:**
  - Model Armor (`modelarmor.<region>.rep.googleapis.com`) is regional (`REGION`), whereas Gemini models (`aiplatform.<multi_region>.rep.googleapis.com`) are multi-regional (`GOOGLE_CLOUD_LOCATION`). Both require their respective regional PSC endpoints in [`0-prereqs/networking.tf`](./0-prereqs/networking.tf) when Cloud Run egress is set to `PRIVATE_RANGES_ONLY`.
- **Container Lockfiles (`uv.lock`):**
  - Each Python sample app under [`1-apps/apps/`](./1-apps/apps) uses `uv sync --frozen` in its `Dockerfile`. Whenever a `pyproject.toml` is updated, run `uv lock` in that app folder and commit the updated `uv.lock`.
