# Cloud Run RAG with Vertex AI Vector Search (`cloud-run-rag-search`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `cloud-run-rag-search` factory deploys a **Retrieval-Augmented Generation (RAG)** application on Cloud Run backed by **Vertex AI Vector Search 2.0 (`vectorsearch.googleapis.com`)** and **Google Cloud Storage**:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) and optional Shared VPC host project (`0-prereqs/data/projects/host.yaml`).
  - VPC, subnet, Private Google Access, Cloud DNS response policies, and regional PSC endpoint (`0-prereqs/networking.tf`) for multi-regional Vertex AI (`aiplatform.<multi_region>.rep.googleapis.com`).
  - Stage 1 RW/RO automation service accounts and dedicated service accounts for the Cloud Run frontend (`roles/vectorsearch.viewer`, `roles/aiplatform.user`), ingestion job (`roles/vectorsearch.dataObjectWriter`, `roles/aiplatform.user`, `roles/storage.objectViewer`), and Cloud Build.
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **Vector Search 2.0 Collection & Optional Index** ([`1-apps/database.tf`](./1-apps/database.tf)): `google_vector_search_collection` configured with `data_schema` (storing movie metadata directly alongside vectors) and `vector_schema` with `vertex_embedding_config` (`gemini-embedding-001`, `3072` dimensions, `RETRIEVAL_DOCUMENT`) for automatic embedding generation. An optional ScaNN ANN `google_vector_search_index` can be enabled via `var.vector_search_config.index_config.create = true` (`false` by default, using zero-indexing kNN out of the box).
  - **Ingestion Pipeline** ([`1-apps/ingestion.tf`](./1-apps/ingestion.tf)): GCS bucket (seeded with [`1-apps/data/data.jsonl`](./1-apps/data/data.jsonl)) and Cloud Run Job that reads JSONL records and batch-upserts `DataObject` items into the Vector Search 2.0 Collection (`google-cloud-vectorsearch`), relying on Vector Search 2.0 auto-embeddings.
  - **Frontend & Load Balancer** ([`1-apps/frontend.tf`](./1-apps/frontend.tf), [`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), [`1-apps/lb-int.tf`](./1-apps/lb-int.tf)): Cloud Run RAG web/API service ([`1-apps/apps/rag/`](./1-apps/apps/rag)) that queries the Vector Search 2.0 Collection using Hybrid Search (`SemanticSearch` + `TextSearch` combined with Reciprocal Rank Fusion `RRF`) and calls `gemini-4-argon`, behind an external or internal Application Load Balancer.

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
  - [`0-prereqs/networking.tf`](./0-prereqs/networking.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/database.tf`](./1-apps/database.tf), [`1-apps/ingestion.tf`](./1-apps/ingestion.tf), [`1-apps/frontend.tf`](./1-apps/frontend.tf), [`1-apps/main.tf`](./1-apps/main.tf), [`1-apps/variables.tf`](./1-apps/variables.tf), [`1-apps/outputs.tf`](./1-apps/outputs.tf)
  - Sample RAG application: [`1-apps/apps/rag/`](./1-apps/apps/rag)
- **Tests** ([`tests/cloud_run_rag_search/`](../tests/cloud_run_rag_search)):
  - `0_prereqs`: `simple`, `no_host_prj`
  - `1_apps`: `simple`

## Testing & Inventory Regeneration

```shell
# Run all cloud-run-rag-search tests
uv run pytest tests/cloud_run_rag_search

# Regenerate 0-prereqs inventories
for t in simple no_host_prj; do
  uv run tools/plan_summary.py cloud-run-rag-search/0-prereqs \
    tests/cloud_run_rag_search/0_prereqs/${t}.tfvars \
    > tests/cloud_run_rag_search/0_prereqs/${t}.yaml
done

# Regenerate 1-apps inventory
uv run tools/plan_summary.py cloud-run-rag-search/1-apps \
  tests/cloud_run_rag_search/1_apps/simple.tfvars \
  > tests/cloud_run_rag_search/1_apps/simple.yaml

# Format regenerated YAML files
uv run yamlfix tests/cloud_run_rag_search
```

## Factory-Specific Learnings & Gotchas

- **Vector Search 2.0 Regional Availability (`europe-west1` vs. `europe-west4`):**
  - While `vectorsearch.googleapis.com` lists `europe-west1` as a location, `CreateCollection` in `europe-west1` fails with `Error code 10, message: Failed to perform tenant project creation`, whereas `europe-west4`, `europe-west2`, `europe-north1`, and `us-central1` succeed.
  - In [`1-apps/database.tf`](./1-apps/database.tf), `local.vector_search_location` defaults to `europe-west4` when `var.region == "europe-west1"` (unless `var.vector_search_config.location` is explicitly set) and passes `VECTOR_SEARCH_LOCATION` to the Cloud Run ingestion job and frontend service.
- **Regional Vector Search vs. Multi-Regional Gemini Models:**
  - Vertex AI Vector Search 2.0 (`google_vector_search_collection` and `google_vector_search_index`) is regional (`local.vector_search_location`), whereas Gemini generative models (`gemini-4-argon`) are called on the multi-regional endpoint (`eu` or `us`). Keep `REGION`, `VECTOR_SEARCH_LOCATION`, and `GOOGLE_CLOUD_LOCATION` distinct in the Cloud Run service and job environment variables.
- **Auto-Embeddings & Upsert Batch Size Limit (`<= 250`):**
  - When a Vector Search 2.0 Collection is configured with `vertex_embedding_config` (auto-embeddings), `DataObject` records are upserted with `vectors={}` and Vector Search generates the embeddings automatically.
  - `batch_create_data_objects` and `batch_update_data_objects` enforce a maximum of `250` items per batch when auto-embeddings are enabled, and `data_object_id` must conform to RFC1035 (`[a-z]([a-z0-9-]{0,61}[a-z0-9])?`).
- **Idempotent Scheduled Ingestion (`AlreadyExists` Fallback):**
  - Because Cloud Scheduler triggers the ingestion job every 30 minutes and `batch_create_data_objects` is not an upsert (it raises `409 AlreadyExists` if any `data_object_id` in the batch already exists), [`upsert_data_objects_to_collection`](./1-apps/apps/rag/ingestion/src/vector_search.py) catches `AlreadyExists` and falls back to `batch_update_data_objects` (which requires `name = "<parent>/dataObjects/<data_object_id>"` on each `DataObject`).
- **Caller IAM for Auto-Embeddings (`roles/aiplatform.user`):**
  - Even though Vector Search 2.0 generates embeddings server-side via `vertex_embedding_config`, both the ingestion service account (`gf-rrag-ing-0`) and the frontend service account (`gf-rrag-fe-0`, when executing `SemanticSearch`) must hold `roles/aiplatform.user` because Vector Search invokes Vertex AI Embeddings on the caller's behalf.
- **Collection Deletion Requires Empty Collection (`COLLECTION_HAS_DATA_OBJECTS`):**
  - `DeleteCollection` (`terraform destroy` on `google_vector_search_collection`) fails with `Error 400: Collection deletion is not allowed because it still has data objects` if `DataObject` records exist in the collection. Delete data objects first via `dataObjects:batchDelete` before destroying a populated collection.
- **Container Lockfiles (`uv.lock`):**
  - Whenever [`1-apps/apps/rag/frontend/pyproject.toml`](./1-apps/apps/rag/frontend/pyproject.toml) or [`1-apps/apps/rag/ingestion/pyproject.toml`](./1-apps/apps/rag/ingestion/pyproject.toml) is updated, run `uv lock` inside the corresponding subfolder so `uv sync --frozen` succeeds during Cloud Build.
