# Cloud Run RAG with Vertex AI Vector Search (`cloud-run-rag-search`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `cloud-run-rag-search` factory deploys a **Retrieval-Augmented Generation (RAG)** application on Cloud Run backed by **Vertex AI Vector Search** and **Google Cloud Storage**:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) and optional Shared VPC host project (`0-prereqs/data/projects/host.yaml`).
  - VPC, subnet, Private Services Access (PSA) range for Vertex AI Vector Search private endpoints, Private Google Access, Cloud DNS response policies, and regional PSC endpoint (`0-prereqs/networking.tf`) for multi-regional Vertex AI (`aiplatform.<multi_region>.rep.googleapis.com`).
  - Stage 1 RW/RO automation service accounts and dedicated service accounts for the Cloud Run frontend, ingestion job, and Cloud Build.
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **Vertex AI Vector Search Index & Endpoint** ([`1-apps/database.tf`](./1-apps/database.tf)): Streaming-update Vector Search index (`3072` dimensions for `gemini-embedding-001`) deployed to a private VPC-peered Index Endpoint.
  - **Ingestion Pipeline** ([`1-apps/ingestion.tf`](./1-apps/ingestion.tf)): GCS bucket (seeded with [`1-apps/data/data.jsonl`](./1-apps/data/data.jsonl)) and Cloud Run Job that reads JSONL records, generates embeddings in batches, and upserts datapoints into the Vector Search index.
  - **Frontend & Load Balancer** ([`1-apps/frontend.tf`](./1-apps/frontend.tf), [`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), [`1-apps/lb-int.tf`](./1-apps/lb-int.tf)): Cloud Run RAG web/API service ([`1-apps/apps/rag/`](./1-apps/apps/rag)) behind an external or internal Application Load Balancer.

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

- **Regional Vector Search vs. Multi-Regional Gemini Models:**
  - Vertex AI Vector Search (`google_vertex_ai_index` and `google_vertex_ai_index_endpoint`) is strictly regional (`var.region`), whereas Gemini models (`gemini-4-argon`, `gemini-embedding-001`) are called on the multi-regional endpoint (`var.multi_region`, e.g., `eu` or `us`). Keep `REGION` and `GOOGLE_CLOUD_LOCATION` separate in the Cloud Run service and job environment variables.
- **Embedding Batch Size Limit (`<= 250`):**
  - `client.models.embed_content` enforces a maximum of `250` inputs per request; always chunk input texts into batches of `<= 250` before calling the embeddings API.
- **Container Lockfiles (`uv.lock`):**
  - Whenever [`1-apps/apps/rag/frontend/pyproject.toml`](./1-apps/apps/rag/frontend/pyproject.toml) or [`1-apps/apps/rag/ingestion/pyproject.toml`](./1-apps/apps/rag/ingestion/pyproject.toml) is updated, run `uv lock` inside the corresponding subfolder so `uv sync --frozen` succeeds during Cloud Build.
