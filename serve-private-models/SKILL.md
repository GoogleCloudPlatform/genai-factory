---
name: genai-factory-serve-private-models
description: Use when deploying or configuring the genai-factory serve-private-models blueprint (Vertex AI Model Garden open models such as Gemma 3 privately exposed via Private Service Connect to a Cloud Run frontend with Load Balancer, Cloud Armor, and Model Armor), configuring model_garden_config (publisher or Hugging Face models on NVIDIA L4 GPUs), or troubleshooting provider region, EULA consent, and GPU quota errors.
---

# GenAI Factory — Serve Private Models (`serve-private-models`)

## Overview

Deploys an open model from **Vertex AI Model Garden** (defaulting to `gemma3@gemma-3-1b-it` on `g2-standard-12` with `1x NVIDIA_L4`) on a private **Vertex AI Endpoint** ([`serve-private-models`](./README.md)) exposed via **Private Service Connect (PSC)** to a **Cloud Run** frontend behind an optional **External or Internal Application Load Balancer**, **Cloud Armor**, and **Model Armor**.

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `serve-private-models`.
- Switching between Model Garden publisher models (`publisher_model_name`) and Hugging Face models (`hugging_face_model_id`), or tuning GPU machine specs/spot capacity (`model_garden_config`).
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO Shared VPC, Fabric FAST, and `aiplatform.<eu|us>.rep.googleapis.com` + `modelarmor.<region>.rep.googleapis.com` PSC/DNS setup.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-cloud-run-and-load-balancers`](../.agents/skills/genai-factory-cloud-run-and-load-balancers/SKILL.md) for `lbs_configs`, Cloud Armor, CAS (`ca_pool_name_suffix`), and Direct Cloud Run ingress.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-model-armor`](../.agents/skills/genai-factory-model-armor/SKILL.md) for `model_armor_template_config` and `model_armor_floorsetting_config`.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT` and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-mg-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-mg-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Default Name (`var.name`)** | `gf-mg-0` ([`1-apps/variables.tf`](./1-apps/variables.tf)) |
| **Required SA Keys (`1-apps`)** | `service-01/iac-rw` (holds custom role `model_garden_deployer` with `aiplatform.consents.update`), `service-01/crun-0` (`aiplatform.user`, `modelarmor.user`), `service-01/crun-build-0` |
| **PSC Consumer Forwarding Rule** | Created in the service project ([`1-apps/model-garden.tf`](./1-apps/model-garden.tf)) targeting the Vertex AI Endpoint's `service_attachment` (`ENDPOINT_IP_ADDRESS`) |

## Core Patterns

### Custom Publisher or Hugging Face Model (`1-apps/terraform.tfvars`)

`publisher_model_name` and `hugging_face_model_id` are mutually exclusive:

```hcl
model_garden_config = {
  accept_eula           = true
  publisher_model_name  = null # Or "publishers/google/models/gemma3@gemma-3-4b-it"
  hugging_face_model_id = "google/gemma-3-1b-it"
  spot                  = false
  min_replica_count     = 1
  max_replica_count     = 2
  machine_spec = {
    machine_type      = "g2-standard-12"
    accelerator_type  = "NVIDIA_L4"
    accelerator_count = 1
  }
}
```

### Deploy & Query the Sample Chat Application (`1-apps/apps/chat`)

After `terraform apply` in `1-apps/` (15–25 minutes for GPU provisioning), run `terraform output -raw commands` to deploy [`1-apps/apps/chat/`](./1-apps/apps/chat/README.md) with `ENDPOINT_ID` and `ENDPOINT_IP_ADDRESS` (uses `aiplatform.PrivateEndpoint.predict(..., endpoint_override=config.ENDPOINT_IP_ADDRESS)`):

```shell
curl -X POST "https://<YOUR_DOMAIN_OR_RUN_URL>/chat" \
  -H "Content-Type: application/json" \
  -d '{"message": "Explain quantum computing in simple terms."}'
```

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| `400 URL notable to be parsed: https://-aiplatform.googleapis.com/...` | `google_vertex_ai_endpoint_with_model_garden_deployment` requires `region` set on the provider block | Set `region = "<region>"` in both `provider "google"` and `provider "google-beta"` in `1-apps/providers.tf`. |
| `403 Permission 'aiplatform.consents.update' denied` | Deployer SA (`service-01/iac-rw`) lacks EULA consent permission for gated models | Ensure `0-prereqs` bound the custom role `model_garden_deployer` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)), or accept the model EULA in the Cloud Console. |
| Cloud Run times out calling `ENDPOINT_IP_ADDRESS` | `cloud_run_config.vpc_access_egress` does not route private RFC1918 traffic to the VPC | Keep `vpc_access_egress = "ALL_TRAFFIC"` (default) or `"PRIVATE_RANGES_ONLY"` with Direct VPC Egress. |
| `QUOTA_EXCEEDED` / `ZONE_RESOURCE_POOL_EXHAUSTED` | Insufficient regional Spot or On-Demand `NVIDIA_L4_GPUS` quota/capacity | Request `NVIDIA_L4_GPUS` quota, set `model_garden_config.spot = false`, or switch regions. |
