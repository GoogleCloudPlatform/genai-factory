# Cloud Run RAG with AlloyDB (`cloud-run-rag-alloydb`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `cloud-run-rag-alloydb` factory deploys a **Retrieval-Augmented Generation (RAG)** application on Cloud Run backed by **AlloyDB for PostgreSQL** (`pgvector` + `scann` vector index) and **BigQuery**:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) and optional Shared VPC host project (`0-prereqs/data/projects/host.yaml`).
  - VPC, subnet, Private Services Access (PSA) range for AlloyDB, Private Google Access, Cloud DNS response policies, and regional PSC endpoint (`0-prereqs/networking.tf`) for multi-regional Vertex AI (`aiplatform.<multi_region>.rep.googleapis.com`).
  - Stage 1 RW/RO automation service accounts and dedicated service accounts for the Cloud Run frontend, ingestion job, and Cloud Build.
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **AlloyDB Cluster & Primary Instance** ([`1-apps/database.tf`](./1-apps/database.tf)): Private IP AlloyDB cluster storing document chunks and `3072`-dimension `gemini-embedding-001` vectors indexed with AlloyDB's `scann` extension.
  - **Ingestion Pipeline** ([`1-apps/ingestion.tf`](./1-apps/ingestion.tf)): GCS bucket (seeded with [`1-apps/data/top-100-imdb-movies.csv`](./1-apps/data/top-100-imdb-movies.csv)), BigQuery dataset/table, and Cloud Run Job that reads from BigQuery, generates embeddings in batches, and populates AlloyDB.
  - **Frontend & Load Balancer** ([`1-apps/frontend.tf`](./1-apps/frontend.tf), [`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), [`1-apps/lb-int.tf`](./1-apps/lb-int.tf)): Cloud Run RAG web/API service ([`1-apps/apps/rag/`](./1-apps/apps/rag)) behind an external or internal Application Load Balancer.

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
  - [`0-prereqs/networking.tf`](./0-prereqs/networking.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/database.tf`](./1-apps/database.tf), [`1-apps/ingestion.tf`](./1-apps/ingestion.tf), [`1-apps/frontend.tf`](./1-apps/frontend.tf), [`1-apps/main.tf`](./1-apps/main.tf), [`1-apps/variables.tf`](./1-apps/variables.tf), [`1-apps/outputs.tf`](./1-apps/outputs.tf)
  - Sample RAG application: [`1-apps/apps/rag/`](./1-apps/apps/rag)
- **Tests** ([`tests/cloud_run_rag_alloydb/`](../tests/cloud_run_rag_alloydb)):
  - `0_prereqs`: `simple`, `no_host_prj`
  - `1_apps`: `simple`

## Testing & Inventory Regeneration

```shell
# Run all cloud-run-rag-alloydb tests
uv run pytest tests/cloud_run_rag_alloydb

# Regenerate 0-prereqs inventories
for t in simple no_host_prj; do
  uv run tools/plan_summary.py cloud-run-rag-alloydb/0-prereqs \
    tests/cloud_run_rag_alloydb/0_prereqs/${t}.tfvars \
    > tests/cloud_run_rag_alloydb/0_prereqs/${t}.yaml
done

# Regenerate 1-apps inventory
uv run tools/plan_summary.py cloud-run-rag-alloydb/1-apps \
  tests/cloud_run_rag_alloydb/1_apps/simple.tfvars \
  > tests/cloud_run_rag_alloydb/1_apps/simple.yaml

# Format regenerated YAML files
uv run yamlfix tests/cloud_run_rag_alloydb
```

## Factory-Specific Learnings & Gotchas

- **3072-Dimension Embeddings & AlloyDB `scann` Index:**
  - `gemini-embedding-001` produces `3072`-dimension vectors (`vector(3072)`). Standard `pgvector` `ivfflat` and `hnsw` indexes on `vector` columns only support up to `2000` dimensions, whereas AlloyDB's `scann` index (`alloydb_scann` extension) supports `3072` dimensions natively.
- **Embedding Batch Size Limit (`<= 250`):**
  - `client.models.embed_content` accepts at most `250` inputs per request; the ingestion job in [`1-apps/apps/rag/`](./1-apps/apps/rag) chunks records into batches of `<= 250`.
- **Container Lockfiles (`uv.lock`):**
  - Whenever [`1-apps/apps/rag/frontend/pyproject.toml`](./1-apps/apps/rag/frontend/pyproject.toml) or [`1-apps/apps/rag/ingestion/pyproject.toml`](./1-apps/apps/rag/ingestion/pyproject.toml) is updated, run `uv lock` inside the corresponding subfolder so `uv sync --frozen` succeeds during Cloud Build.
