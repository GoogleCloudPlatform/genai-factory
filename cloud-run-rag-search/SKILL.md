---
name: genai-factory-cloud-run-rag-search
description: Use when deploying or configuring the genai-factory cloud-run-rag-search blueprint (Cloud Run RAG frontend and scheduled GCS ingestion job backed by Vertex AI Vector Search 2.0 Collections with auto-embeddings and Hybrid Search / RRF), customizing vector_search_config or ScaNN ANN indexes, or troubleshooting europe-west1 tenant creation and COLLECTION_HAS_DATA_OBJECTS errors on destroy.
---

# GenAI Factory — Cloud Run RAG with Vector Search 2.0 (`cloud-run-rag-search`)

## Overview

Deploys a **Cloud Run RAG frontend** and **scheduled GCS ingestion Cloud Run job** ([`cloud-run-rag-search`](./README.md)) backed by **Vertex AI Vector Search 2.0 Collections** (`google_vector_search_collection`) with server-side auto-embeddings (`gemini-embedding-001`, `3072` dims) and **Hybrid Search** (`SemanticSearch` + `TextSearch` via Reciprocal Rank Fusion `RRF`).

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `cloud-run-rag-search`.
- Configuring `vector_search_config` (collection schema or optional ScaNN ANN `google_vector_search_index`), uploading JSONL data to GCS, or running the ingestion/frontend workloads.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO Shared VPC, Fabric FAST, and `aiplatform.<eu|us>.rep.googleapis.com` PSC/DNS setup.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-cloud-run-and-load-balancers`](../.agents/skills/genai-factory-cloud-run-and-load-balancers/SKILL.md) for `lbs_configs`, `cloud_run_configs`, `ingestion_schedule_configs`, and container builds.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT` and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-rrag-src-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-rrag-src-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Default Name (`var.name`)** | `gf-rrag-search-0` (requires `var.prefix` in `1-apps` for GCS bucket `module.index-bucket`) |
| **Required SA Keys (`1-apps`)** | `service-01/iac-rw`, `service-01/gf-rrag-fe-0` (`vectorsearch.viewer`, `aiplatform.user`), `service-01/gf-rrag-ing-0` (`vectorsearch.dataObjectWriter`, `storage.objectViewer`, `aiplatform.user`), `*-build-0`, `service-01/gf-rrag-ing-sched-0` |
| **Collection Location** | Automatically maps `europe-west1` -> `europe-west4` in [`1-apps/database.tf`](./1-apps/database.tf) (`VECTOR_SEARCH_LOCATION`) |

## Core Patterns

### Enable Optional Dedicated ScaNN ANN Index (`1-apps/terraform.tfvars`)

By default (`index_config.create = false`), the collection uses zero-indexing exact kNN search. To provision a dedicated ScaNN ANN index:

```hcl
vector_search_config = {
  location = "europe-west4"
  index_config = {
    create            = true
    distance_metric   = "DOT_PRODUCT"
    feature_norm_type = "UNIT_L2_NORM"
    filter_fields     = ["genre", "year", "rating", "rank"]
    store_fields      = ["title"]
    mode              = "STORAGE_OPTIMIZED"
    min_replica_count = 2
    max_replica_count = 2
  }
}
```

### 4-Step Deployment & Ingestion Sequence

After `terraform apply` in `1-apps/`, run `terraform output -raw commands` ([`1-apps/outputs.tf`](./1-apps/outputs.tf)) to:

1. **Upload JSONL to GCS:** Copy [`1-apps/data/data.jsonl`](./1-apps/data/data.jsonl) to `gs://<prefix>-gf-rrag-search-0/data.jsonl`.
2. **Create Artifact Registry:** Docker repo `${var.name}` in `${var.region}`.
3. **Build, Deploy & Run Ingestion Job ([`1-apps/apps/rag/ingestion/`](./1-apps/apps/rag/ingestion)):** Batch-upserts `DataObject` items (`<= 100` per batch, max `250`, falling back from `batch_create_data_objects` to `batch_update_data_objects` on `409 AlreadyExists`).
4. **Build, Deploy & Query Frontend ([`1-apps/apps/rag/frontend/`](./1-apps/apps/rag/frontend/README.md)):** Queries `POST /predict` using Hybrid Search (`SemanticSearch` + `TextSearch` RRF).

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| `Error code 10: Failed to perform tenant project creation` on Collection create | Vector Search 2.0 Collections are not available in `europe-west1` | Keep the [`1-apps/database.tf`](./1-apps/database.tf) fallback (`europe-west4`) and keep `REGION`, `VECTOR_SEARCH_LOCATION`, and `GOOGLE_CLOUD_LOCATION` (`eu`/`us`) distinct. |
| `403 Permission denied` during server-side auto-embedding upsert or `SemanticSearch` | Caller SA lacks Vertex AI permission to invoke `gemini-embedding-001` | Ensure both `gf-rrag-ing-0` and `gf-rrag-fe-0` have `roles/aiplatform.user`. |
| `400: Collection deletion is not allowed because it still has data objects` on `terraform destroy` | `DeleteCollection` rejects non-empty collections | Delete all `DataObject` records via `dataObjects:batchDelete` before running `terraform destroy` on `1-apps`. |
| Invalid `data_object_id` or batch size error during ingestion | `DataObject` IDs must be RFC1035 (`[a-z]([a-z0-9-]{0,61}[a-z0-9])?`) and batches `<= 250` | Sanitize IDs to RFC1035 and keep `VECTOR_SEARCH_UPSERT_BATCH_SIZE <= 250`. |
