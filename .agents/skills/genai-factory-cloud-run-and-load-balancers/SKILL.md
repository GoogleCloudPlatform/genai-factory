---
name: genai-factory-cloud-run-and-load-balancers
description: Use when configuring Cloud Run services or scheduled RAG ingestion jobs in genai-factory, setting up External HTTPS or Internal Application Load Balancers (lbs_configs), Cloud Armor IP allowlists, Certificate Authority Service (ca_pool_name_suffix), Direct Cloud Run ingress, or building container images with Cloud Build.
---

# GenAI Factory Cloud Run, Load Balancers & Scheduled Jobs

## Overview

Configures the shared Cloud Run service, External/Internal Application Load Balancer (`lbs_configs`), Certificate Authority Service (`ca_pool_name_suffix`), and scheduled Cloud Run Job (`cloud_run_job_config`) interfaces used across `cloud-run-*` and `serve-private-models` factories.

## When to Use

- Configuring `lbs_configs`, `ca_pool_name_suffix`, `cloud_run_config`, or `cloud_run_job_config` in `1-apps/terraform.tfvars`.
- Exposing a Cloud Run service via External HTTPS GLB, Internal ALB with private CAS certificates, or Direct Cloud Run `.run.app` ingress.
- Building and deploying sample applications via `terraform output -raw commands`.
- **REQUIRED SUB-SKILL for Quota & Teardown Issues:** Use [`genai-factory-operations-and-teardown`](../genai-factory-operations-and-teardown/SKILL.md).

## Quick Reference — Ingress & Job Variables

| Variable | Key Attributes & Defaults | Notes |
| :--- | :--- | :--- |
| `lbs_configs.external` | `enable = true`, `domain = "example.com"`, `allowed_ip_ranges = ["0.0.0.0/0"]` | Provisions Google-managed SSL cert + Cloud Armor IP allowlist |
| `lbs_configs.internal` | `enable = false`, `domain = "example.com"`, `allowed_ip_ranges = ["0.0.0.0/0"]` | Regional Internal ALB + CAS private TLS cert |
| `ca_pool_name_suffix` | `"ca-pool-0"` | Must be globally unique per project/region if recreated within 30 days |
| `cloud_run_config` | `ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"`, `vpc_access_egress` | Set `ingress = "INGRESS_TRAFFIC_ALL"` only when both LBs are disabled |
| `cloud_run_job_config` | `schedule = "0 0 * * *"`, `time_zone = "Etc/UTC"`, `max_retries = 0` | Used in `cloud-run-rag-*` factories for scheduled ingestion |

## Core Patterns

### Pattern 1: External & Internal Load Balancers (`1-apps/terraform.tfvars`)

```hcl
ca_pool_name_suffix = "ca-pool-rag-01" # Required when internal.enable = true

lbs_configs = {
  external = {
    enable            = true
    domain            = "ai.example.com"
    allowed_ip_ranges = ["203.0.113.10/32"]
  }
  internal = {
    enable            = true
    domain            = "ai.internal.example.com"
    allowed_ip_ranges = ["10.0.0.0/8"]
  }
}
```

### Pattern 2: Direct Cloud Run Ingress (No Load Balancers)

```hcl
lbs_configs = {
  external = { enable = false }
  internal = { enable = false }
}

cloud_run_config = {
  ingress          = "INGRESS_TRAFFIC_ALL"
  service_invokers = ["user:developer@example.com"]
}
```

### Pattern 3: Customizing Scheduled RAG Ingestion Jobs (`cloud-run-rag-*`)

```hcl
cloud_run_job_config = {
  schedule    = "0 */6 * * *"
  time_zone   = "Europe/Rome"
  max_retries = 1
}
```

### Python Application & Container Build Rules

- **Separate `REGION` and `GOOGLE_CLOUD_LOCATION`:** Keep `REGION` (`europe-west1`) for regional APIs (Model Armor, AlloyDB, Cloud SQL) and `GOOGLE_CLOUD_LOCATION` (`eu` or `us`) for multi-regional Gemini models in `google-genai` / `google-adk`.
- **Update `uv.lock` on Dependency Edits:** Sample app `Dockerfile`s run `uv sync --frozen` (or `--locked`). Always run `uv lock` inside the app folder after editing `pyproject.toml`.

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| `409 Conflict: CaPool already exists / pending deletion` | GCP CAS retains deleted CA pools for 30 days | Set a new unique `ca_pool_name_suffix` in `1-apps/terraform.tfvars` |
| Cloud Build fails with lockfile out-of-sync error | `pyproject.toml` was edited without updating `uv.lock` | Run `uv lock` in the sample app directory before `gcloud builds submit` / `gcloud run deploy` |
| External SSL certificate stuck in `PROVISIONING` | Public DNS A-record does not point to `ip_addresses.external` | Point `lbs_configs.external.domain` to `terraform output ip_addresses` |
