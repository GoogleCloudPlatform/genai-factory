---
name: cloud-run-rag-cloudsql
description: >-
  Actionable runbook for configuring, deploying, customizing, and operating the
  cloud-run-rag-cloudsql factory (Cloud Run RAG frontend and scheduled BigQuery
  ingestion job backed by Cloud SQL for PostgreSQL with pgvector over Private
  Service Connect). Use this skill whenever a user asks to deploy or configure
  cloud-run-rag-cloudsql, tune Cloud SQL or ingestion scheduler variables,
  build and run the BigQuery-to-Cloud-SQL embedding pipeline, or troubleshoot
  Cloud SQL Auth Proxy PSC connectivity and pgvector 3072-dimension indexing.
---

# Cloud Run RAG with Cloud SQL (`cloud-run-rag-cloudsql`) Skill

This skill provides the factory-specific specifications, configuration recipes, and application/ingestion playbook for deploying and operating the `cloud-run-rag-cloudsql` blueprint.

> [!NOTE]
>
> - For shared prerequisite workflows (`0-prereqs`, BYO Shared VPC, Fabric FAST), load [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md).
> - For Load Balancer (`lbs_configs`), Cloud Armor, CAS (`ca_pool_name_suffix`), Direct Cloud Run access (`cloud_run_configs`), and Python container build patterns, load [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).
> - For E2E troubleshooting and teardown, load [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md).
> - For repository contributor rules and test inventory regeneration, see [`AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Factory Identity & Stage 0 (`0-prereqs`) Specification

Follow the step-by-step workflows in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) (Standalone `0-prereqs`, Bring Your Own Shared VPC, or Fabric FAST) using these `cloud-run-rag-cloudsql` identifiers:

| Component | Factory Value / Definition | Notes |
| :--- | :--- | :--- |
| **Default Resource / Project Name (`var.name`)** | `gf-rrag-0` | Defined in [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml) and [`1-apps/variables.tf`](./1-apps/variables.tf). BigQuery dataset/table ID uses underscores (`gf_rrag_0`). |
| **Host Project Name** *(when `networking_config.create = true`)* | `gf-rrag-hp-0` | Defined in [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml). |
| **Required `service_account_emails` & `service_account_ids` Keys** | `service-01/iac-rw`<br>`service-01/gf-rrag-fe-0`<br>`service-01/gf-rrag-fe-build-0`<br>`service-01/gf-rrag-ing-0`<br>`service-01/gf-rrag-ing-build-0`<br>`service-01/gf-rrag-ing-sched-0` | Stage 1 automation SA (`iac-rw`), Frontend runtime & build SAs (`gf-rrag-fe-*`), Ingestion job runtime & build SAs (`gf-rrag-ing-*`), and Cloud Scheduler trigger SA (`gf-rrag-ing-sched-0`). |
| **Host Project IAM** *(critical for BYO Shared VPC / FAST)* | `roles/compute.networkUser` & `roles/dns.admin` for `service-01/iac-rw`<br>`roles/compute.networkUser` for `service-01/run` service agent | `service-01/iac-rw` creates the Cloud SQL PSC consumer IP/forwarding rule and binds the private Cloud DNS zone (`gf-rrag-0-cloudsql`) to the Shared VPC ([`1-apps/database.tf`](./1-apps/database.tf)). |
| **Regional PSC Endpoints (`0-prereqs/networking.tf`)** | `aiplatform.<eu\|us>.rep.googleapis.com` | Defined in [`0-prereqs/networking.tf`](./0-prereqs/networking.tf). Required for multi-regional Gemini and embedding calls over private VPC egress. |

______________________________________________________________________

## 2. Stage 1 (`1-apps`) Configuration (`terraform.tfvars`)

Stage 1 variables are declared in [`1-apps/variables.tf`](./1-apps/variables.tf) (and [`1-apps/variables-fast.tf`](./1-apps/variables-fast.tf) for FAST integration).

- **Exposure Layer & Scheduled Ingestion (`lbs_configs`, `ca_pool_name_suffix`, `cloud_run_configs`, `ingestion_schedule_configs`)**:
  - Supports **External HTTPS Load Balancer** ([`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), enabled by default), **Internal Application Load Balancer + CAS** ([`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/lb-int-cert.tf`](./1-apps/lb-int-cert.tf)), or **Direct Cloud Run Access** on `cloud_run_configs.frontend` (`INGRESS_TRAFFIC_ALL`), plus Cloud Scheduler tuning via `ingestion_schedule_configs`.
  - Use the recipes in [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).

### Factory-Specific Recipe — Cloud SQL Instance Sizing & High Availability (`db_configs`)

[`1-apps/database.tf`](./1-apps/database.tf) provisions a Cloud SQL for PostgreSQL instance exposed privately via Private Service Connect (`psc_config`) with IAM database authentication enabled (`cloudsql.iam_authentication = "on"`). Both `gf-rrag-fe-0` and `gf-rrag-ing-0` (`cloudsqlsuperuser`) are registered as `CLOUD_IAM_SERVICE_ACCOUNT` users.

```hcl
db_configs = {
  availability_type = "REGIONAL"        # Or "ZONAL" for dev/test cost savings
  database_version  = "POSTGRES_14"
  tier              = "db-custom-2-7680" # Default is "db-f1-micro"
  flags = {
    "cloudsql.iam_authentication" = "on"
  }
}
```

> [!IMPORTANT]
> Always keep `"cloudsql.iam_authentication" = "on"` in `db_configs.flags` because both the frontend service ([`1-apps/frontend.tf`](./1-apps/frontend.tf)) and the ingestion job ([`1-apps/ingestion.tf`](./1-apps/ingestion.tf)) connect through a `cloud-sql-proxy` sidecar container configured with `--psc --auto-iam-authn`.

______________________________________________________________________

## 3. Data Seeding, Ingestion & Frontend Deployment Playbook

After `terraform apply` finishes in [`1-apps/`](./1-apps), run `terraform output -raw commands` to retrieve the four-step deployment sequence ([`1-apps/outputs.tf`](./1-apps/outputs.tf)):

1. **Seed BigQuery with Sample Movie Data**:
   - Loads [`1-apps/data/top-100-imdb-movies.csv`](./1-apps/data/top-100-imdb-movies.csv) into the BigQuery table `<project_id>:gf_rrag_0.gf_rrag_0` using `bq load` while impersonating `service-01/iac-rw`.
2. **Create Artifact Registry Repository**:
   - Creates the Docker repository `${var.name}` in `${var.region}`.
3. **Build, Deploy & Execute the Ingestion Cloud Run Job ([`1-apps/apps/rag/ingestion/`](./1-apps/apps/rag/ingestion))**:
   - Submits `./apps/rag/ingestion` via Cloud Build (`service-01/gf-rrag-ing-build-0`).
   - Updates the job container (`gcloud run jobs deploy ${var.name}-ingestion --container=ingestion ...`) and runs it synchronously (`gcloud run jobs execute ${var.name}-ingestion --wait`).
   - **What the ingestion job does**: Reads records from BigQuery (`BQ_DATASET`, `BQ_TABLE`), generates `3072`-dimension `gemini-embedding-001` vectors in batches (`BATCH_SIZE_EMBEDDING = 25` in [`ingestion/src/config.py`](./1-apps/apps/rag/ingestion/src/config.py)), enables the `vector` extension (`pgvector`), and populates the Cloud SQL table (`DB_TABLE`).
4. **Build, Deploy & Verify the Frontend Cloud Run Service ([`1-apps/apps/rag/frontend/`](./1-apps/apps/rag/frontend))**:
   - Submits `./apps/rag/frontend` via Cloud Build (`service-01/gf-rrag-fe-build-0`).

   - Updates the frontend container (`gcloud run deploy ${var.name}-frontend --container=frontend ...`).

   - **Verify RAG Retrieval & Generation** ([`frontend/README.md`](./1-apps/apps/rag/frontend/README.md)):

     ```shell
     curl -X POST https://<YOUR_DOMAIN_OR_RUN_URL>/predict \
       -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
       -H "Content-Type: application/json" \
       -d '{"prompt":"Can you recommend a great action movie?"}'
     ```

### Key Environment Variables

| Component | Config File | Required Env Vars (Set by Terraform Output) | Optional Tuning Env Vars (With Defaults) |
| :--- | :--- | :--- | :--- |
| **Ingestion Job** | [`1-apps/apps/rag/ingestion/src/config.py`](./1-apps/apps/rag/ingestion/src/config.py) | `PROJECT_ID`, `REGION`, `BQ_DATASET`, `BQ_TABLE`, `DB_NAME`, `DB_SA`, `DB_TABLE` | `EMBEDDING_MODEL_NAME` (`gemini-embedding-001`), `EMBEDDING_DIMENSIONS` (`3072`), `BATCH_SIZE_EMBEDDING` (`25`, max `250`), `BQ_TEXT_COLUMNS` (`title,description`) |
| **Frontend Service** | [`1-apps/apps/rag/frontend/src/config.py`](./1-apps/apps/rag/frontend/src/config.py) | `PROJECT_ID`, `REGION`, `DB_NAME`, `DB_SA`, `DB_TABLE` | `GOOGLE_CLOUD_LOCATION` (`eu`), `MODEL_NAME` (`gemini-4-argon`), `THINKING_LEVEL` (`MEDIUM`), `EMBEDDING_MODEL_NAME` (`gemini-embedding-001`), `RETRIEVER_TOP_K` (`10`) |

______________________________________________________________________

## 4. Factory-Specific Gotchas & Troubleshooting

In addition to the shared troubleshooting procedures in [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md):

1. **`pgvector` `3072`-Dimension Indexing Limit on Cloud SQL**:
   - `gemini-embedding-001` defaults to `3072` dimensions (`vector(3072)`). Standard PostgreSQL `pgvector` `ivfflat` and `hnsw` indexes on `vector` columns only support up to `2000` dimensions.
   - Do **not** create an `ivfflat` or `hnsw` index on a `vector(3072)` column in Cloud SQL — either rely on exact KNN search on `vector(3072)` (the default in this factory) or reduce `EMBEDDING_DIMENSIONS` to `<= 2000` (or use `halfvec` casts) if an ANN index is required.
2. **Always Pass `--container=frontend` / `--container=ingestion` on Deploy**:
   - Both the Cloud Run service and job run a second sidecar container (`cloud-sql-proxy` / `cloudsql-proxy`) listening on `127.0.0.1:5432`. Omitting `--container` during `gcloud run deploy` or `gcloud run jobs deploy` can overwrite the wrong container spec.
3. **Format of `DB_SA` for Cloud SQL IAM Auth**:
   - PostgreSQL IAM service account usernames omit the `.gserviceaccount.com` suffix (e.g., `my-sa@my-project.iam`). [`1-apps/outputs.tf`](./1-apps/outputs.tf) strips `.gserviceaccount.com` automatically when constructing `DB_SA`; preserve this format if overriding `DB_SA` manually.
4. **Two Separate `uv.lock` Files**:
   - [`1-apps/apps/rag/frontend/`](./1-apps/apps/rag/frontend) and [`1-apps/apps/rag/ingestion/`](./1-apps/apps/rag/ingestion) have independent `pyproject.toml` and `uv.lock` files. Run `uv lock` inside the respective subfolder whenever its `pyproject.toml` is modified.
