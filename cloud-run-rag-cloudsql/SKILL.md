---
name: genai-factory-cloud-run-rag-cloudsql
description: Use when deploying or configuring the genai-factory cloud-run-rag-cloudsql blueprint (Cloud Run RAG frontend and scheduled BigQuery ingestion job backed by Cloud SQL for PostgreSQL with pgvector over Private Service Connect), tuning db_configs, running the BigQuery-to-Cloud-SQL embedding pipeline, or troubleshooting Cloud SQL Auth Proxy PSC connectivity and pgvector 3072-dimension indexing limits.
---

# GenAI Factory — Cloud Run RAG with Cloud SQL (`cloud-run-rag-cloudsql`)

## Overview

Deploys a **Cloud Run RAG frontend** and **scheduled BigQuery ingestion Cloud Run job** ([`cloud-run-rag-cloudsql`](./README.md)) backed by **Cloud SQL for PostgreSQL (`pgvector`)** exposed privately via **Private Service Connect (PSC)** and accessed via a `cloud-sql-proxy` (`--psc --auto-iam-authn`) sidecar.

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `cloud-run-rag-cloudsql`.
- Tuning Cloud SQL (`db_configs`), seeding BigQuery, running the ingestion job (`apps/rag/ingestion`), or deploying the RAG frontend (`apps/rag/frontend`).
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO Shared VPC, Fabric FAST, and `aiplatform.<eu|us>.rep.googleapis.com` PSC/DNS setup.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-cloud-run-and-load-balancers`](../.agents/skills/genai-factory-cloud-run-and-load-balancers/SKILL.md) for `lbs_configs`, `cloud_run_configs`, `ingestion_schedule_configs`, and container builds.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT` and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-rrag-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-rrag-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Default Name (`var.name`)** | `gf-rrag-0` (BQ dataset/table: `gf_rrag_0`, Cloud DNS zone: `gf-rrag-0-cloudsql`) |
| **Required SA Keys (`1-apps`)** | `service-01/iac-rw`, `service-01/gf-rrag-fe-0`, `service-01/gf-rrag-fe-build-0`, `service-01/gf-rrag-ing-0`, `service-01/gf-rrag-ing-build-0`, `service-01/gf-rrag-ing-sched-0` |
| **Host Project IAM** | `compute.networkUser` & `dns.admin` for `service-01/iac-rw` (creates Cloud SQL PSC consumer IP/forwarding rule & private DNS zone); `compute.networkUser` for `service-01/run` |

## Core Patterns

### Tune Cloud SQL Instance Sizing (`1-apps/terraform.tfvars`)

```hcl
db_configs = {
  availability_type = "REGIONAL"        # Or "ZONAL" for dev/test
  database_version  = "POSTGRES_14"
  tier              = "db-custom-2-7680" # Default: "db-f1-micro"
  flags = {
    "cloudsql.iam_authentication" = "on" # Required for sidecar --auto-iam-authn
  }
}
```

### 4-Step Deployment & Ingestion Sequence

After `terraform apply` in `1-apps/`, run `terraform output -raw commands` ([`1-apps/outputs.tf`](./1-apps/outputs.tf)) to:

1. **Seed BigQuery:** `bq load` [`1-apps/data/top-100-imdb-movies.csv`](./1-apps/data/top-100-imdb-movies.csv) into `<project_id>:gf_rrag_0.gf_rrag_0`.
2. **Create Artifact Registry:** Docker repo `${var.name}` in `${var.region}`.
3. **Build, Deploy & Run Ingestion Job ([`1-apps/apps/rag/ingestion/`](./1-apps/apps/rag/ingestion)):** Reads BigQuery rows, generates `3072`-dimension `gemini-embedding-001` vectors (`BATCH_SIZE_EMBEDDING=25`), enables `vector` (`pgvector`), and upserts into Cloud SQL (`DB_TABLE`).
4. **Build, Deploy & Query Frontend ([`1-apps/apps/rag/frontend/`](./1-apps/apps/rag/frontend/README.md)):**

```shell
curl -X POST "https://<YOUR_DOMAIN_OR_RUN_URL>/predict" \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Can you recommend a great action movie?"}'
```

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| `column cannot have more than 2000 dimensions for ivfflat/hnsw index` | Standard `pgvector` `ivfflat` and `hnsw` indexes cap `vector` columns at `2000` dimensions | Use exact kNN search on `vector(3072)` (the factory default), reduce `EMBEDDING_DIMENSIONS <= 2000`, or cast to `halfvec` (or use [`genai-factory-cloud-run-rag-alloydb`](../cloud-run-rag-alloydb/SKILL.md) for 3072-dim `scann`). |
| `gcloud run deploy` or `jobs deploy` breaks the `cloud-sql-proxy` sidecar | Both [`1-apps/frontend.tf`](./1-apps/frontend.tf) and [`1-apps/ingestion.tf`](./1-apps/ingestion.tf) run a `cloud-sql-proxy` sidecar | Always include `--container=frontend` or `--container=ingestion`. |
| Cloud SQL IAM login fails when overriding `DB_SA` | PostgreSQL IAM usernames omit `.gserviceaccount.com` | Format `DB_SA` as `<sa-name>@<project-id>.iam` (without `.gserviceaccount.com`). |
| Cloud Build fails on `uv sync --frozen` | Separate `uv.lock` files in `frontend/` and `ingestion/` | Run `uv lock` inside the modified subfolder before building. |
