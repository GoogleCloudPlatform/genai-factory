---
name: genai-factory-cloud-run-nl2sql-bq
description: Use when deploying or configuring the genai-factory cloud-run-nl2sql-bq blueprint (Natural Language to SQL Google ADK agent on Cloud Run querying BigQuery), pointing the bigquery_agent at a custom BigQuery dataset (BQ_DATA_PROJECT_ID, BQ_DATASET_ID), enabling the ADK web interface (SERVE_WEB_INTERFACE), or troubleshooting BigQuery IAM permissions.
---

# GenAI Factory — Cloud Run NL2SQL on BigQuery (`cloud-run-nl2sql-bq`)

## Overview

Deploys a **Google ADK Natural Language to SQL (`bigquery_agent`)** application ([`cloud-run-nl2sql-bq`](./README.md)) on **Cloud Run** behind an External or Internal Application Load Balancer that inspects BigQuery table schemas and executes read-only SQL queries.

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `cloud-run-nl2sql-bq`.
- Pointing `bigquery_agent` ([`1-apps/apps/nl2sql/`](./1-apps/apps/nl2sql/README.md)) at a custom BigQuery dataset or enabling `SERVE_WEB_INTERFACE=True`.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO Shared VPC, Fabric FAST, and `aiplatform.<eu|us>.rep.googleapis.com` PSC/DNS setup.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-cloud-run-and-load-balancers`](../.agents/skills/genai-factory-cloud-run-and-load-balancers/SKILL.md) for `lbs_configs`, Cloud Armor, CAS (`ca_pool_name_suffix`), Direct Cloud Run ingress (`cloud_run_config`), and container builds.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT` and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-nl2sql-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-nl2sql-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Default Name (`var.name`)** | `nl2sql-0` ([`1-apps/variables.tf`](./1-apps/variables.tf)) |
| **Required SA Keys (`1-apps`)** | `service-01/iac-rw`, `service-01/nl2sql-0` (runtime: `bigquery.user`, `bigquery.dataViewer`, `aiplatform.user`), `service-01/nl2sql-build-0` |
| **Key App Env Vars** | `PROJECT_ID`, `REGION`, `GOOGLE_CLOUD_LOCATION` (`eu`/`us`), `MODEL_NAME` (`gemini-4-argon`), `THINKING_LEVEL` (`MEDIUM`), `BQ_DATA_PROJECT_ID` (`bigquery-public-data`), `BQ_DATASET_ID` (`thelook_ecommerce`), `SERVE_WEB_INTERFACE` (`False`) — see [`config.py`](./1-apps/apps/nl2sql/src/config.py) |

## Core Patterns

### Deploy Sample App & Query `bigquery_agent`

After `terraform apply` in `1-apps/`, run `terraform output -raw commands` to create the Artifact Registry repo, build `./apps/nl2sql` with Cloud Build, and deploy to Cloud Run. Verify with ([`1-apps/apps/nl2sql/README.md`](./1-apps/apps/nl2sql/README.md)):

```shell
export APP_ADDRESS="https://<YOUR_DOMAIN_OR_RUN_URL>"
TOKEN="$(gcloud auth print-identity-token)"

# 1. Create an ADK session
curl -X POST "${APP_ADDRESS}/apps/bigquery_agent/users/u1/sessions/s1" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"state": {"preferred_language": "English"}}'

# 2. Run a natural language query
curl -X POST "${APP_ADDRESS}/run_sse" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"app_name":"bigquery_agent","user_id":"u1","session_id":"s1","new_message":{"role":"user","parts":[{"text":"Which 5 users have the most orders?"}]},"streaming":false}'
```

### Point to a Custom BigQuery Dataset

Override `BQ_DATA_PROJECT_ID` and `BQ_DATASET_ID` in `--set-env-vars` on `gcloud run deploy`, and grant `roles/bigquery.dataViewer` on the target dataset/project to `service-01/nl2sql-0` (`roles/bigquery.user` on `PROJECT_ID` is already granted to run query jobs).

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| `403 Access Denied: Table ...: User does not have permission to query table` | Custom dataset is in another project where `service-01/nl2sql-0` lacks read access | Grant `roles/bigquery.dataViewer` on the external dataset/project to `service-01/nl2sql-0`. |
| `gcloud builds submit` fails on `uv sync --frozen` | Modified [`pyproject.toml`](./1-apps/apps/nl2sql/pyproject.toml) without updating [`uv.lock`](./1-apps/apps/nl2sql/uv.lock) | Run `uv lock` inside `1-apps/apps/nl2sql/` before building. |
