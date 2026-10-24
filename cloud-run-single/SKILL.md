---
name: cloud-run-single
description: >-
  Actionable runbook for configuring, deploying, customizing, testing, and
  troubleshooting a single containerized GenAI application, ADK agent, A2A
  server, GPU-accelerated Gemma model, or FastMCP server on Cloud Run using the
  cloud-run-single factory. Use this skill whenever a user asks to deploy or
  configure cloud-run-single, choose between its prerequisite modes (0-prereqs,
  BYO-VPC, or Fabric FAST), craft terraform.tfvars recipes (External/Internal
  Load Balancers, Cloud Armor, NVIDIA L4 GPU, Model Armor), build or adapt an
  application on top of the deployed infrastructure, or debug E2E deployment
  and teardown issues.
---

# Cloud Run Single (`cloud-run-single`) Skill

This skill provides the factory-specific specifications, configuration recipes, and application playbook for deploying and operating the `cloud-run-single` blueprint.

> [!NOTE]
>
> - For shared prerequisite workflows (`0-prereqs`, BYO Shared VPC, Fabric FAST), load [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md).
> - For Load Balancer (`lbs_configs`), Cloud Armor, CAS (`ca_pool_name_suffix`), and Cloud Run/Build patterns, load [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).
> - For Model Armor template and floor setting tuning, load [`model-armor`](../.agents/skills/model-armor/SKILL.md).
> - For E2E troubleshooting and teardown, load [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md).
> - For repository contributor rules and test inventory regeneration, see [`AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Factory Identity & Stage 0 (`0-prereqs`) Specification

Follow the step-by-step workflows in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) (Standalone `0-prereqs`, Bring Your Own Shared VPC, or Fabric FAST) using these `cloud-run-single` resource identifiers:

| Component | Factory Value / Definition | Notes |
| :--- | :--- | :--- |
| **Default Resource / Project Name (`var.name`)** | `gf-srun-0` | Defined in [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml) and [`1-apps/variables.tf`](./1-apps/variables.tf). |
| **Host Project Name** *(when `networking_config.create = true`)* | `gf-srun-hp-0` | Defined in [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml). |
| **Required `service_account_emails` & `service_account_ids` Keys** | `service-01/iac-rw`<br>`service-01/crun-0`<br>`service-01/crun-build-0` | Stage 1 Terraform/CLI automation SA, Cloud Run runtime SA (`roles/aiplatform.user`, `roles/modelarmor.user`), and Cloud Build SA. |
| **Regional PSC Endpoints (`0-prereqs/networking.tf`)** | `aiplatform.<eu\|us>.rep.googleapis.com`<br>`modelarmor.<region>.rep.googleapis.com` | Defined in [`0-prereqs/networking.tf`](./0-prereqs/networking.tf). Both are required in the host VPC when Cloud Run uses `PRIVATE_RANGES_ONLY` or private `ALL_TRAFFIC` egress. |

______________________________________________________________________

## 2. Stage 1 (`1-apps`) Configuration (`terraform.tfvars`)

Stage 1 variables are declared in [`1-apps/variables.tf`](./1-apps/variables.tf) (and [`1-apps/variables-fast.tf`](./1-apps/variables-fast.tf) for FAST integration).

- **Exposure Layer (`lbs_configs`, `ca_pool_name_suffix`, `cloud_run_config.ingress`)**:
  - Supports **External HTTPS Load Balancer** ([`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), enabled by default), **Internal Application Load Balancer + CAS** ([`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/lb-int-cert.tf`](./1-apps/lb-int-cert.tf)), or **Direct Cloud Run Access** (`INGRESS_TRAFFIC_ALL`).
  - Use the `terraform.tfvars` snippets in [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).
- **Model Armor (`model_armor_template_config` & `model_armor_floorsetting_config`)**:
  - Defined in [`1-apps/model-armor.tf`](./1-apps/model-armor.tf); both are enabled by default with `INSPECT_AND_BLOCK` and `HIGH` confidence thresholds.
  - Use the configuration recipes in [`model-armor`](../.agents/skills/model-armor/SKILL.md) to tune filter thresholds or disable project-wide floor settings.

### Factory-Specific Recipe — NVIDIA L4 GPU Acceleration (for Self-Hosted Gemma / Ollama / vLLM)

To run GPU-backed workloads such as [`1-apps/apps/gemma/`](./1-apps/apps/gemma) on Cloud Run Gen2 ([`1-apps/main.tf`](./1-apps/main.tf)), configure `cloud_run_config` in `1-apps/terraform.tfvars`:

```hcl
cloud_run_config = {
  gpu_zonal_redundancy_disabled = true
  node_selector = {
    accelerator = "nvidia-l4"
  }
  containers = {
    ai = {
      image = "us-docker.pkg.dev/cloudrun/container/gemma/gemma3-4b:latest"
      resources = {
        limits = {
          cpu              = "8"
          memory           = "32Gi"
          "nvidia.com/gpu" = "1"
        }
      }
    }
  }
}
```

______________________________________________________________________

## 3. Application Selection & Deployment Playbook (`1-apps/apps/`)

After `terraform apply` finishes in [`1-apps/`](./1-apps), run `terraform output -raw commands` to get the pre-populated Artifact Registry, Cloud Build, and `gcloud run deploy` commands. Follow the application conventions in [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md) and select from the five workloads below:

| Workload | Directory | Port | Key Env Vars | Use Case & Verification |
| :--- | :--- | :--- | :--- | :--- |
| **Chat** | [`1-apps/apps/chat/`](./1-apps/apps/chat) | `8080` | `PROJECT_ID`, `REGION`, `GOOGLE_CLOUD_LOCATION` (`eu`/`us`), `MODEL_NAME` (`gemini-4-argon`), `THINKING_LEVEL` (`MEDIUM`), `MODEL_ARMOR_TEMPLATE` | FastAPI + `google-genai` backend with explicit Model Armor prompt/response sanitization ([`config.py`](./1-apps/apps/chat/src/config.py)). Verify with `POST /predict` (`{"prompt": "hello"}`). |
| **ADK Agent** | [`1-apps/apps/adk/`](./1-apps/apps/adk) | `8080` | Same as `chat` + `SERVE_WEB_INTERFACE` (`True`/`False`), `SESSION_DB_URL` | Google ADK agent (`capital_agent`) with Model Armor callbacks ([`config.py`](./1-apps/apps/adk/src/config.py)). Verify with `GET /list-apps`, `POST /apps/capital_agent/users/u1/sessions/s1`, and `POST /run_sse`. |
| **ADK with A2A** | [`1-apps/apps/adk-a2a/`](./1-apps/apps/adk-a2a) | `8003` | Same as `chat` + `A2A_URL` (public/internal LB domain or Cloud Run URI) | Exposes an ADK agent via Agent2Agent (A2A) protocol ([`config.py`](./1-apps/apps/adk-a2a/src/config.py)). **Must** pass `--port=8003` and `A2A_URL` on `gcloud run deploy`. Verify with `GET /.well-known/agent-card.json`. |
| **Gemma 3 on GPU** | [`1-apps/apps/gemma/`](./1-apps/apps/gemma) | `8080` | `OLLAMA_NUM_PARALLEL=4` | Deploys pre-built `us-docker.pkg.dev/cloudrun/container/gemma/gemma3-4b:latest` (no `gcloud builds submit` step required). Requires the **NVIDIA L4 GPU recipe** above. Verify with `POST /api/generate`. |
| **MCP Server** | [`1-apps/apps/mcp-server/`](./1-apps/apps/mcp-server) | `8080` | `PORT=8080` | FastMCP server that extracts caller OAuth credentials from request headers to list/create/delete GCP firewall rules. Caller needs `roles/compute.securityAdmin`. Verify with `uv run client.py https://<DOMAIN>/mcp list`. |

______________________________________________________________________

## 4. Troubleshooting & Teardown

Refer to [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md) for:

- Resolving `403 Permission 'serviceusage.services.use' denied` during `gcloud` service account impersonation (`export CLOUDSDK_BILLING_QUOTA_PROJECT="<service-project-id>"`).
- Debugging `.rep.googleapis.com` timeouts on private VPC egress.
- Handling `serverless-ipv4-cloudrun-*` subnet IP reservation delays on `0-prereqs` teardown and removing generated `1-apps/providers.tf` and `1-apps/terraform.auto.tfvars` files.
