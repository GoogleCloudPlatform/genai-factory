---
name: genai-factory-cloud-run-rag-alloydb
description: Use when deploying or configuring the genai-factory cloud-run-rag-alloydb blueprint (Cloud Run RAG frontend and scheduled BigQuery ingestion job backed by AlloyDB for PostgreSQL with pgvector and alloydb_scann over Private Service Connect), building and running the BigQuery-to-AlloyDB embedding pipeline, or troubleshooting AlloyDB PSC and IAM authentication.
---

# GenAI Factory — Cloud Run RAG with AlloyDB (`cloud-run-rag-alloydb`)

## Overview

Deploys a **Cloud Run RAG frontend** and **scheduled BigQuery ingestion Cloud Run job** ([`cloud-run-rag-alloydb`](./README.md)) backed by **AlloyDB for PostgreSQL** (`pgvector` + `alloydb_scann` index) exposed privately via **Private Service Connect (PSC)** with IAM database authentication.

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `cloud-run-rag-alloydb`.
- Seeding BigQuery, building/executing the AlloyDB ingestion job (`apps/rag/ingestion`), or deploying the RAG frontend (`apps/rag/frontend`).
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO Shared VPC, Fabric FAST, and `aiplatform.<eu|us>.rep.googleapis.com` PSC/DNS setup.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-cloud-run-and-load-balancers`](../.agents/skills/genai-factory-cloud-run-and-load-balancers/SKILL.md) for `lbs_configs`, `cloud_run_configs`, `ingestion_schedule_configs`, and container builds.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT` and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-rrag-all-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-rrag-all-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Default Name (`var.name`)** | `gf-rrag-0` (AlloyDB cluster: `alloydb`, primary instance: `${var.name}`, BQ dataset/table: `gf_rrag_0`) |
| **Required `var.number`** | Service project number (authorizes `psc_config.allowed_consumer_projects` in [`1-apps/database.tf`](./1-apps/database.tf)) |
| **Required SA Keys (`1-apps`)** | `service-01/iac-rw`, `service-01/gf-rrag-fe-0`, `service-01/gf-rrag-fe-build-0`, `service-01/gf-rrag-ing-0`, `service-01/gf-rrag-ing-build-0`, `service-01/gf-rrag-ing-sched-0` |
| **Host Project IAM** | `compute.networkUser` & `dns.admin` for `service-01/iac-rw` (creates PSC forwarding rule & private DNS zone `${var.name}-alloydb`); `compute.networkUser` for `service-01/run` |

## Core Patterns

### 4-Step Deployment & Ingestion Sequence

After `terraform apply` in `1-apps/`, run `terraform output -raw commands` ([`1-apps/outputs.tf`](./1-apps/outputs.tf)) to execute:

1. **Seed BigQuery:** `bq load` [`1-apps/data/top-100-imdb-movies.csv`](./1-apps/data/top-100-imdb-movies.csv) into `<project_id>:gf_rrag_0.gf_rrag_0`.
2. **Create Artifact Registry:** Docker repo `${var.name}` in `${var.region}`.
3. **Build, Deploy & Run Ingestion Job ([`1-apps/apps/rag/ingestion/`](./1-apps/apps/rag/ingestion)):** Connects to AlloyDB over PSC (`Connector(ip_type="PSC", enable_iam_auth=True)`), enables `vector` + `alloydb_scann`, embeds BigQuery rows with `gemini-embedding-001` (`3072` dims, `BATCH_SIZE_EMBEDDING=25`), and upserts them.
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
| `gcloud run deploy` or `jobs deploy` overwrites the `alloydb-proxy` sidecar | Both [`1-apps/frontend.tf`](./1-apps/frontend.tf) and [`1-apps/ingestion.tf`](./1-apps/ingestion.tf) define a multi-container spec with `alloydb-proxy` | Always pass `--container=frontend` or `--container=ingestion` on deploy. |
| Index creation fails with `column cannot have more than 2000 dimensions` | Used standard `pgvector` `ivfflat` or `hnsw` index on `vector(3072)` | Use AlloyDB's `scann` index (`CREATE EXTENSION IF NOT EXISTS alloydb_scann; CREATE INDEX ... USING scann (embedding cosine)`), which natively supports `3072` dimensions. |
| AlloyDB connection fails after renaming cluster/instance in `database.tf` | [`frontend/src/config.py`](./1-apps/apps/rag/frontend/src/config.py) and [`ingestion/src/config.py`](./1-apps/apps/rag/ingestion/src/config.py) construct `clusters/alloydb/instances/{DB_NAME}` | Update `ALLOYDB_INSTANCE_URI` in both `config.py` files if cluster/instance names change. |
| Cloud Build fails on `uv sync --frozen` | Frontend and ingestion have separate `uv.lock` files | Run `uv lock` inside the modified subfolder (`frontend/` or `ingestion/`). |
