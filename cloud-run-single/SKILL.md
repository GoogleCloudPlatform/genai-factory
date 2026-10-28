---
name: genai-factory-cloud-run-single
description: Use when deploying or configuring the genai-factory cloud-run-single blueprint for a single Cloud Run GenAI application (chat, Google ADK agent, ADK with A2A server, Gemma 3 on NVIDIA L4 GPU, or FastMCP server) with External/Internal Application Load Balancer, Cloud Armor, and Model Armor.
---

# GenAI Factory — Cloud Run Single (`cloud-run-single`)

## Overview

Deploys a single **Cloud Run Gen2** service ([`cloud-run-single`](./README.md)) fronted by an optional **External or Internal Application Load Balancer**, **Cloud Armor**, and **Model Armor**, supporting five sample workloads under [`1-apps/apps/`](./1-apps/apps/): `chat`, `adk`, `adk-a2a`, `gemma` (on NVIDIA L4 GPU), and `mcp-server`.

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `cloud-run-single`.
- Enabling NVIDIA L4 GPU acceleration (`cloud_run_config.node_selector`) or deploying any of the 5 sample apps (`chat`, `adk`, `adk-a2a`, `gemma`, `mcp-server`).
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO Shared VPC, Fabric FAST, and `aiplatform.<eu|us>.rep.googleapis.com` + `modelarmor.<region>.rep.googleapis.com` PSC/DNS setup.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-cloud-run-and-load-balancers`](../.agents/skills/genai-factory-cloud-run-and-load-balancers/SKILL.md) for `lbs_configs`, Cloud Armor, CAS (`ca_pool_name_suffix`), and Direct Cloud Run ingress.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-model-armor`](../.agents/skills/genai-factory-model-armor/SKILL.md) for `model_armor_template_config` and `model_armor_floorsetting_config`.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT` and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-srun-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-srun-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Default Name (`var.name`)** | `gf-srun-0` ([`1-apps/variables.tf`](./1-apps/variables.tf)) |
| **Required SA Keys (`1-apps`)** | `service-01/iac-rw`, `service-01/crun-0` (`aiplatform.user`, `modelarmor.user`), `service-01/crun-build-0` |
| **Regional PSC Endpoints** | `aiplatform.<eu/us>.rep.googleapis.com` and `modelarmor.<region>.rep.googleapis.com` ([`0-prereqs/networking.tf`](./0-prereqs/networking.tf)) |

## Core Patterns

### NVIDIA L4 GPU Acceleration for Gemma / Ollama (`1-apps/terraform.tfvars`)

```hcl
cloud_run_config = {
  gpu_zonal_redundancy_disabled = true
  node_selector                 = { accelerator = "nvidia-l4" }
  containers = {
    ai = {
      image = "us-docker.pkg.dev/cloudrun/container/gemma/gemma3-4b:latest"
      resources = {
        limits = { cpu = "8", memory = "32Gi", "nvidia.com/gpu" = "1" }
      }
    }
  }
}
```

### Sample Workloads (`1-apps/apps/`)

Run `terraform output -raw commands` after `terraform apply` in `1-apps/`:

| Workload | Directory | Port | Key Env Vars & Verification |
| :--- | :--- | :--- | :--- |
| **Chat** | [`apps/chat/`](./1-apps/apps/chat) | `8080` | `PROJECT_ID`, `REGION`, `GOOGLE_CLOUD_LOCATION` (`eu`/`us`), `MODEL_NAME` (`gemini-4-argon`), `THINKING_LEVEL` (`MEDIUM`), `MODEL_ARMOR_TEMPLATE`. Verify: `POST /predict` (`{"prompt":"hello"}`). |
| **ADK Agent** | [`apps/adk/`](./1-apps/apps/adk) | `8080` | Same as `chat` + `SERVE_WEB_INTERFACE`, `SESSION_DB_URL`. Verify: `GET /list-apps`, `POST /apps/capital_agent/users/u1/sessions/s1`, `POST /run_sse`. |
| **ADK + A2A** | [`apps/adk-a2a/`](./1-apps/apps/adk-a2a) | `8003` | Same as `chat` + `A2A_URL` (LB or Run URL) and `--port=8003`. Verify: `GET /.well-known/agent-card.json`. |
| **Gemma 3 GPU** | [`apps/gemma/`](./1-apps/apps/gemma) | `8080` | `OLLAMA_NUM_PARALLEL=4` (uses pre-built image, no Cloud Build step). Verify: `POST /api/generate`. |
| **MCP Server** | [`apps/mcp-server/`](./1-apps/apps/mcp-server) | `8080` | `PORT=8080` (caller needs `roles/compute.securityAdmin`). Verify: `uv run client.py https://<DOMAIN>/mcp list`. |

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| `apps/adk-a2a` fails health check or returns wrong URL in `agent-card.json` | `adk-a2a` listens on port `8003` and requires `A2A_URL` | Pass `--port=8003` and `A2A_URL=https://<DOMAIN>` on `gcloud run deploy`. |
| Model Armor calls time out from Cloud Run | Missing regional PSC endpoint for `modelarmor.<region>.rep.googleapis.com` in BYO-VPC | Provision the regional PSC endpoint and DNS rule per [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md). |
