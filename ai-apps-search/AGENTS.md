# AI Applications — Search (`ai-apps-search`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `ai-apps-search` factory deploys a **Vertex AI Search (Discovery Engine)** application backed by an unstructured Google Cloud Storage data store:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) with Discovery Engine and Cloud Storage APIs enabled.
  - Stage 1 RW/RO automation service accounts and Discovery Engine service agent permissions (`roles/storage.objectViewer`).
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **GCS Bucket** ([`1-apps/main.tf`](./1-apps/main.tf)): Stores unstructured source documents (e.g., PDFs) for indexing.
  - **Discovery Engine Data Store & Search Engine** ([`1-apps/main.tf`](./1-apps/main.tf)): Provisions `google_discovery_engine_data_store` (`CONTENT_REQUIRED`, `SOLUTION_TYPE_SEARCH`) and `google_discovery_engine_search_engine`.
  - **Outputs** ([`1-apps/outputs.tf`](./1-apps/outputs.tf)): Prints `curl` / `gcloud` commands to upload sample PDFs, trigger `import_documents`, and query the search engine.

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/main.tf`](./0-prereqs/main.tf), [`0-prereqs/variables.tf`](./0-prereqs/variables.tf), [`0-prereqs/outputs.tf`](./0-prereqs/outputs.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/main.tf`](./1-apps/main.tf), [`1-apps/variables.tf`](./1-apps/variables.tf), [`1-apps/outputs.tf`](./1-apps/outputs.tf)
- **Tests** ([`tests/ai_apps_search/`](../tests/ai_apps_search)):
  - `0_prereqs`: `simple`
  - `1_apps`: `simple`

## Testing & Inventory Regeneration

```shell
# Run all ai-apps-search tests
uv run pytest tests/ai_apps_search

# Regenerate 0-prereqs inventory
uv run tools/plan_summary.py ai-apps-search/0-prereqs \
  tests/ai_apps_search/0_prereqs/simple.tfvars \
  > tests/ai_apps_search/0_prereqs/simple.yaml

# Regenerate 1-apps inventory
uv run tools/plan_summary.py ai-apps-search/1-apps \
  tests/ai_apps_search/1_apps/simple.tfvars \
  > tests/ai_apps_search/1_apps/simple.yaml

# Format regenerated YAML files
uv run yamlfix tests/ai_apps_search
```

## Factory-Specific Learnings & Gotchas

- **Document Processing Config (`document_processing_config`):**
  - Always configure `document_processing_config` (including `default_parsing_config { digital_parsing_config {} }`) directly on the `google_discovery_engine_data_store` resource in [`1-apps/main.tf`](./1-apps/main.tf) so unstructured document imports (`import_documents`) work immediately after provisioning.
- **Discovery Engine Service Agent Permissions:**
  - The Discovery Engine service agent (`service-<project_number>@gcp-sa-discoveryengine.iam.gserviceaccount.com`) must have `roles/storage.objectViewer` on the source GCS bucket before running `import_documents`.
