---
name: cloud-run-nl2sql-bq
description: >-
  Actionable runbook for configuring, deploying, customizing, and operating the
  cloud-run-nl2sql-bq factory (Natural Language to SQL Google ADK agent on Cloud
  Run querying BigQuery behind an External or Internal Application Load
  Balancer). Use this skill whenever a user asks to deploy or configure
  cloud-run-nl2sql-bq, point the NL2SQL ADK agent at a custom BigQuery dataset,
  enable the ADK web interface, or troubleshoot BigQuery permissions and private
  VPC egress.
---

# Cloud Run NL2SQL with BigQuery (`cloud-run-nl2sql-bq`) Skill

This skill provides the factory-specific specifications, configuration recipes, and application playbook for deploying and operating the `cloud-run-nl2sql-bq` blueprint.

> [!NOTE]
>
> - For shared prerequisite workflows (`0-prereqs`, BYO Shared VPC, Fabric FAST), load [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md).
> - For Load Balancer (`lbs_configs`), Cloud Armor, CAS (`ca_pool_name_suffix`), Direct Cloud Run access (`cloud_run_config`), and Python container build patterns, load [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).
> - For E2E troubleshooting and teardown, load [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md).
> - For repository contributor rules and test inventory regeneration, see [`AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Factory Identity & Stage 0 (`0-prereqs`) Specification

Follow the step-by-step workflows in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) (Standalone `0-prereqs`, Bring Your Own Shared VPC, or Fabric FAST) using these `cloud-run-nl2sql-bq` identifiers:

| Component | Factory Value / Definition | Notes |
| :--- | :--- | :--- |
| **Service Project Name (`0-prereqs`)** | `gf-nl2sql-0` | Defined in [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml). |
| **Host Project Name** *(when `networking_config.create = true`)* | `gf-nl2sql-hp-0` | Defined in [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml). |
| **Default Stage 1 Resource Name (`var.name`)** | `nl2sql-0` | Defined in [`1-apps/variables.tf`](./1-apps/variables.tf). |
| **Required `service_account_emails` & `service_account_ids` Keys** | `service-01/iac-rw`<br>`service-01/nl2sql-0`<br>`service-01/nl2sql-build-0` | Stage 1 automation SA (`iac-rw`), Cloud Run runtime SA (`nl2sql-0`, granted `roles/bigquery.user`, `roles/bigquery.dataViewer`, and `roles/aiplatform.user`), and Cloud Build SA (`nl2sql-build-0`). |
| **Regional PSC Endpoints (`0-prereqs/networking.tf`)** | `aiplatform.<eu\|us>.rep.googleapis.com` | Defined in [`0-prereqs/networking.tf`](./0-prereqs/networking.tf). Required for multi-regional Gemini calls over private VPC egress. |

______________________________________________________________________

## 2. Stage 1 (`1-apps`) Configuration (`terraform.tfvars`)

Stage 1 variables are declared in [`1-apps/variables.tf`](./1-apps/variables.tf) (and [`1-apps/variables-fast.tf`](./1-apps/variables-fast.tf) for FAST integration).

- **Exposure Layer (`lbs_configs`, `ca_pool_name_suffix`, `cloud_run_config.ingress`)**:
  - Supports **External HTTPS Load Balancer** ([`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), enabled by default), **Internal Application Load Balancer + CAS** ([`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/lb-int-cert.tf`](./1-apps/lb-int-cert.tf)), or **Direct Cloud Run Access** (`INGRESS_TRAFFIC_ALL`).
  - Use the single-service `terraform.tfvars` snippets in [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).

______________________________________________________________________

## 3. Application Deployment, Customization & Verification Playbook

After `terraform apply` finishes in [`1-apps/`](./1-apps), run `terraform output -raw commands` to retrieve the Artifact Registry, Cloud Build, and `gcloud run deploy` commands ([`1-apps/outputs.tf`](./1-apps/outputs.tf)).

### Sample Workload: ADK BigQuery Agent ([`1-apps/apps/nl2sql/`](./1-apps/apps/nl2sql))

The sample application exposes a Google ADK agent (`bigquery_agent`) via FastAPI that inspects BigQuery table schemas and executes read-only SQL queries.

- **Default Target Dataset**: By default, [`1-apps/outputs.tf`](./1-apps/outputs.tf) configures `BQ_DATA_PROJECT_ID=bigquery-public-data` and `BQ_DATASET_ID=thelook_ecommerce` while billing BigQuery jobs to the service project (`BQ_COMPUTE_PROJECT_ID=PROJECT_ID`).
- **Pointing to a Custom BigQuery Dataset**:
  1. Override `BQ_DATA_PROJECT_ID` and `BQ_DATASET_ID` in `--set-env-vars` on `gcloud run deploy`.
  2. If the dataset is in a different project, grant `roles/bigquery.dataViewer` on that dataset/project to the `service-01/nl2sql-0` service account (`roles/bigquery.user` on `PROJECT_ID` is already granted for running query jobs).

### Environment Variables ([`1-apps/apps/nl2sql/src/config.py`](./1-apps/apps/nl2sql/src/config.py))

| Env Var | Default / Source | Purpose |
| :--- | :--- | :--- |
| `PROJECT_ID` | Set by Terraform output | GCP service project ID (also default for `BQ_COMPUTE_PROJECT_ID`). |
| `REGION` | Set by Terraform output (`europe-west1`) | Regional resource location. |
| `GOOGLE_CLOUD_LOCATION` | `eu` | Multi-regional Vertex AI endpoint (`eu` or `us`) used by `google-adk`. |
| `MODEL_NAME` | `gemini-4-argon` | Gemini model used by `bigquery_agent`. |
| `THINKING_LEVEL` | `MEDIUM` | Reasoning depth passed to `ThinkingConfig`. |
| `BQ_DATA_PROJECT_ID` | `bigquery-public-data` | Project containing the BigQuery dataset to query. |
| `BQ_DATASET_ID` | `thelook_ecommerce` | BigQuery dataset ID exposed to the ADK BigQuery toolset. |
| `SERVE_WEB_INTERFACE` | `False` | Set to `True` to enable the built-in ADK web UI in a browser. |

### Verification Commands ([`1-apps/apps/nl2sql/README.md`](./1-apps/apps/nl2sql/README.md))

```shell
export APP_ADDRESS="https://<YOUR_DOMAIN_OR_RUN_URL>"

# 1. List available ADK apps (should return ["bigquery_agent"])
curl -X GET "${APP_ADDRESS}/list-apps" \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)"

# 2. Create a session for bigquery_agent
curl -X POST "${APP_ADDRESS}/apps/bigquery_agent/users/user_123/sessions/session_abc" \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"state": {"preferred_language": "English"}}'

# 3. Query bigquery_agent in natural language
curl -X POST "${APP_ADDRESS}/run_sse" \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "app_name": "bigquery_agent",
    "user_id": "user_123",
    "session_id": "session_abc",
    "new_message": {
      "role": "user",
      "parts": [{"text": "Which 5 users have the most orders?"}]
    },
    "streaming": false
  }'
```

______________________________________________________________________

## 4. Troubleshooting & Teardown

Refer to [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md) and [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md) for:

- Setting `export CLOUDSDK_BILLING_QUOTA_PROJECT="<service-project-id>"` before running `gcloud` commands with `--impersonate-service-account`.
- Updating [`1-apps/apps/nl2sql/uv.lock`](./1-apps/apps/nl2sql/uv.lock) via `uv lock` whenever [`1-apps/apps/nl2sql/pyproject.toml`](./1-apps/apps/nl2sql/pyproject.toml) changes.
- Clean teardown ordering and removing generated `1-apps/providers.tf` and `1-apps/terraform.auto.tfvars` files.
