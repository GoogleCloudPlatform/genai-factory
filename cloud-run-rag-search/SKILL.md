---
name: cloud-run-rag-search
description: >-
  Actionable runbook for configuring, deploying, customizing, and operating the
  cloud-run-rag-search factory (Cloud Run RAG frontend and scheduled GCS
  ingestion job backed by Vertex AI Vector Search 2.0 Collections with
  auto-embeddings and Hybrid Search / Reciprocal Rank Fusion). Use this skill
  whenever a user asks to deploy or configure cloud-run-rag-search, customize
  Vector Search 2.0 collection schemas or optional ScaNN ANN indexes, run the
  GCS-to-Vector-Search ingestion job, or troubleshoot regional availability and
  collection teardown.
---

# Cloud Run RAG with Vertex AI Vector Search 2.0 (`cloud-run-rag-search`) Skill

This skill provides the factory-specific specifications, configuration recipes, and application/ingestion playbook for deploying and operating the `cloud-run-rag-search` blueprint.

> [!NOTE]
>
> - For shared prerequisite workflows (`0-prereqs`, BYO Shared VPC, Fabric FAST), load [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md).
> - For Load Balancer (`lbs_configs`), Cloud Armor, CAS (`ca_pool_name_suffix`), Direct Cloud Run access (`cloud_run_configs`), scheduled ingestion (`ingestion_schedule_configs`), and Python container build patterns, load [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).
> - For E2E troubleshooting and teardown, load [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md).
> - For repository contributor rules and test inventory regeneration, see [`AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Factory Identity & Stage 0 (`0-prereqs`) Specification

Follow the step-by-step workflows in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) (Standalone `0-prereqs`, Bring Your Own Shared VPC, or Fabric FAST) using these `cloud-run-rag-search` identifiers:

| Component | Factory Value / Definition | Notes |
| :--- | :--- | :--- |
| **Service Project Name (`0-prereqs`)** | `gf-rrag-src-0` | Defined in [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml). |
| **Host Project Name** *(when `networking_config.create = true`)* | `gf-rrag-src-hp-0` | Defined in [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml). |
| **Default Stage 1 Resource Name (`var.name`)** | `gf-rrag-search-0` | Defined in [`1-apps/variables.tf`](./1-apps/variables.tf). Also requires `var.prefix` in Stage 1 for the GCS source bucket (`module.index-bucket`). |
| **Required `service_account_emails` & `service_account_ids` Keys** | `service-01/iac-rw`<br>`service-01/gf-rrag-fe-0`<br>`service-01/gf-rrag-fe-build-0`<br>`service-01/gf-rrag-ing-0`<br>`service-01/gf-rrag-ing-build-0`<br>`service-01/gf-rrag-ing-sched-0` | Stage 1 automation SA (`iac-rw`), Frontend runtime SA (`gf-rrag-fe-0`, granted `roles/vectorsearch.viewer` & `roles/aiplatform.user`), Ingestion job SA (`gf-rrag-ing-0`, granted `roles/vectorsearch.dataObjectWriter`, `roles/storage.objectViewer`, & `roles/aiplatform.user`), build SAs (`*-build-0`), and Cloud Scheduler SA (`gf-rrag-ing-sched-0`). |
| **Host Project IAM** *(for BYO Shared VPC / FAST)* | `roles/compute.networkUser` for `service-01/iac-rw` and `service-01/run` service agent | Defined in [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml). |
| **Regional PSC Endpoints (`0-prereqs/networking.tf`)** | `aiplatform.<eu\|us>.rep.googleapis.com` | Defined in [`0-prereqs/networking.tf`](./0-prereqs/networking.tf). |

______________________________________________________________________

## 2. Stage 1 (`1-apps`) Configuration (`terraform.tfvars`)

Stage 1 variables are declared in [`1-apps/variables.tf`](./1-apps/variables.tf) (and [`1-apps/variables-fast.tf`](./1-apps/variables-fast.tf) for FAST integration).

- **Exposure Layer & Scheduled Ingestion (`lbs_configs`, `ca_pool_name_suffix`, `cloud_run_configs`, `ingestion_schedule_configs`)**:
  - Supports **External HTTPS Load Balancer** ([`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), enabled by default), **Internal Application Load Balancer + CAS** ([`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/lb-int-cert.tf`](./1-apps/lb-int-cert.tf)), or **Direct Cloud Run Access** on `cloud_run_configs.frontend` (`INGRESS_TRAFFIC_ALL`), plus Cloud Scheduler tuning via `ingestion_schedule_configs`.
  - Use the recipes in [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).

### Factory-Specific Recipe — Vector Search 2.0 Collection & Optional ScaNN ANN Index (`vector_search_config`)

By default, [`1-apps/database.tf`](./1-apps/database.tf) provisions a `google_vector_search_collection` configured with:

- `data_schema`: Stores movie metadata (`title`, `description`, `genre`, `year`, `rating`, `rank`) directly on each `DataObject`.
- `vector_schema`: Configures `text_embedding` with `vertex_embedding_config` (`gemini-embedding-001`, `3072` dimensions, `RETRIEVAL_DOCUMENT`) so Vector Search 2.0 generates embeddings automatically on upsert.
- `index_config.create = false` (default): Uses zero-indexing exact kNN search out of the box without dedicated index replica cost.

To enable a dedicated ScaNN ANN `google_vector_search_index` or override the collection location/schema:

```hcl
vector_search_config = {
  location = "europe-west4" # Defaults to "europe-west4" when var.region == "europe-west1"
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

______________________________________________________________________

## 3. Data Upload, Ingestion & Frontend Deployment Playbook

After `terraform apply` finishes in [`1-apps/`](./1-apps), run `terraform output -raw commands` to retrieve the deployment sequence ([`1-apps/outputs.tf`](./1-apps/outputs.tf)):

1. **Upload Sample JSONL Data to GCS**:
   - Copies [`1-apps/data/data.jsonl`](./1-apps/data/data.jsonl) to `gs://<prefix>-gf-rrag-search-0/data.jsonl` using `gcloud storage cp` while impersonating `service-01/iac-rw`.
2. **Create Artifact Registry Repository**:
   - Creates the Docker repository `${var.name}` in `${var.region}`.
3. **Build, Deploy & Execute the Ingestion Cloud Run Job ([`1-apps/apps/rag/ingestion/`](./1-apps/apps/rag/ingestion))**:
   - Submits `./apps/rag/ingestion` via Cloud Build (`service-01/gf-rrag-ing-build-0`).
   - Updates the job container (`gcloud run jobs deploy ${var.name}-ingestion --container=ingestion ...`) and runs it synchronously (`gcloud run jobs execute ${var.name}-ingestion --wait`).
   - **What the ingestion job does** ([`ingestion/src/vector_search.py`](./1-apps/apps/rag/ingestion/src/vector_search.py)): Reads JSONL records from GCS and batch-upserts `DataObject` items (`vectors={}`, relying on Vector Search 2.0 server-side auto-embeddings) in batches of `<= 100` (max `250`). If `batch_create_data_objects` raises `409 AlreadyExists` on re-runs, it automatically falls back to `batch_update_data_objects`.
4. **Build, Deploy & Verify the Frontend Cloud Run Service ([`1-apps/apps/rag/frontend/`](./1-apps/apps/rag/frontend))**:
   - Submits `./apps/rag/frontend` via Cloud Build (`service-01/gf-rrag-fe-build-0`).

   - Updates the frontend container (`gcloud run deploy ${var.name}-frontend --container=frontend ...`).

   - **What the frontend does**: Executes Hybrid Search (`SemanticSearch` + `TextSearch` combined via Reciprocal Rank Fusion `RRF`) against the Vector Search 2.0 Collection and passes the retrieved context to `gemini-4-argon`.

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
| **Ingestion Job** | [`1-apps/apps/rag/ingestion/src/config.py`](./1-apps/apps/rag/ingestion/src/config.py) | `PROJECT_ID`, `REGION`, `GCS_SOURCE_BUCKET`, `VECTOR_SEARCH_COLLECTION_ID`, `VECTOR_SEARCH_LOCATION` | `GCS_SOURCE_BLOB_NAME` (`data.jsonl`), `VECTOR_SEARCH_UPSERT_BATCH_SIZE` (`100`, max `250`) |
| **Frontend Service** | [`1-apps/apps/rag/frontend/src/config.py`](./1-apps/apps/rag/frontend/src/config.py) | `PROJECT_ID`, `REGION`, `VECTOR_SEARCH_COLLECTION_ID`, `VECTOR_SEARCH_LOCATION` | `GOOGLE_CLOUD_LOCATION` (`eu`/`us`), `MODEL_NAME` (`gemini-4-argon`), `THINKING_LEVEL` (`MEDIUM`), `VECTOR_SEARCH_EMBEDDING_FIELD` (`text_embedding`), `VECTOR_SEARCH_TASK_TYPE` (`QUESTION_ANSWERING`), `VECTOR_SEARCH_TEXT_FIELDS` (`title,description,genre`), `RETRIEVER_TOP_K` (`10`) |

______________________________________________________________________

## 4. Factory-Specific Gotchas & Troubleshooting

In addition to the shared troubleshooting procedures in [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md):

1. **Vector Search 2.0 Regional Availability (`europe-west1` -> `europe-west4` Fallback)**:
   - Creating a Vector Search 2.0 Collection in `europe-west1` fails with `Error code 10: Failed to perform tenant project creation`. [`1-apps/database.tf`](./1-apps/database.tf) automatically maps `local.vector_search_location` to `europe-west4` when `var.region == "europe-west1"` (unless `var.vector_search_config.location` is explicitly set) and passes `VECTOR_SEARCH_LOCATION` to both Cloud Run workloads.
   - Always keep `REGION` (Cloud Run location), `VECTOR_SEARCH_LOCATION` (Collection location), and `GOOGLE_CLOUD_LOCATION` (`eu` / `us` for Gemini models) distinct.
2. **Caller IAM for Server-Side Auto-Embeddings (`roles/aiplatform.user`)**:
   - Even though Vector Search 2.0 generates embeddings server-side via `vertex_embedding_config`, both the ingestion SA (`gf-rrag-ing-0`) and the frontend SA (`gf-rrag-fe-0`, when running `SemanticSearch`) **must** have `roles/aiplatform.user`.
3. **RFC1035 `data_object_id` & Batch Limit (`<= 250`)**:
   - Every `DataObject` ID must match `[a-z]([a-z0-9-]{0,61}[a-z0-9])?`, and `batch_create_data_objects` / `batch_update_data_objects` allow at most `250` items per call when auto-embeddings are enabled.
4. **Empty the Collection Before `terraform destroy` (`COLLECTION_HAS_DATA_OBJECTS`)**:
   - `DeleteCollection` fails with `400: Collection deletion is not allowed because it still has data objects` if any `DataObject` records remain in the collection. Delete all data objects via `dataObjects:batchDelete` before running `terraform destroy` on `1-apps`.
