# Cloud Run NL2SQL with BigQuery (`cloud-run-nl2sql-bq`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `cloud-run-nl2sql-bq` factory deploys a **Natural Language to SQL (NL2SQL)** ADK agent on Cloud Run that translates user questions into BigQuery SQL queries:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project (`0-prereqs/data/projects/service-01.yaml`) and optional Shared VPC host project (`0-prereqs/data/projects/host.yaml`).
  - VPC, subnet, Private Google Access, Cloud DNS response policies, and regional PSC endpoint (`0-prereqs/networking.tf`) for multi-regional Vertex AI (`aiplatform.<multi_region>.rep.googleapis.com`).
  - Stage 1 RW/RO automation service accounts and Cloud Run / Cloud Build service accounts.
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **BigQuery Dataset & Table** ([`1-apps/main.tf`](./1-apps/main.tf)): Target dataset queried by the NL2SQL agent.
  - **Cloud Run Service & Artifact Registry** ([`1-apps/main.tf`](./1-apps/main.tf)): Runs the NL2SQL container ([`1-apps/apps/nl2sql/`](./1-apps/apps/nl2sql)) with Direct VPC egress (`PRIVATE_RANGES_ONLY`).
  - **Application Load Balancer & Cloud Armor** ([`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), [`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/lb-int-cert.tf`](./1-apps/lb-int-cert.tf)): External or internal HTTPS load balancer fronting Cloud Run.

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
  - [`0-prereqs/networking.tf`](./0-prereqs/networking.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/main.tf`](./1-apps/main.tf), [`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), [`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/variables.tf`](./1-apps/variables.tf), [`1-apps/outputs.tf`](./1-apps/outputs.tf)
  - Sample application: [`1-apps/apps/nl2sql/`](./1-apps/apps/nl2sql)
- **Tests** ([`tests/cloud_run_nl2sql_bq/`](../tests/cloud_run_nl2sql_bq)):
  - `0_prereqs`: `simple`, `no_host_prj`
  - `1_apps`: `simple`

## Testing & Inventory Regeneration

```shell
# Run all cloud-run-nl2sql-bq tests
uv run pytest tests/cloud_run_nl2sql_bq

# Regenerate 0-prereqs inventories
for t in simple no_host_prj; do
  uv run tools/plan_summary.py cloud-run-nl2sql-bq/0-prereqs \
    tests/cloud_run_nl2sql_bq/0_prereqs/${t}.tfvars \
    > tests/cloud_run_nl2sql_bq/0_prereqs/${t}.yaml
done

# Regenerate 1-apps inventory
uv run tools/plan_summary.py cloud-run-nl2sql-bq/1-apps \
  tests/cloud_run_nl2sql_bq/1_apps/simple.tfvars \
  > tests/cloud_run_nl2sql_bq/1_apps/simple.yaml

# Format regenerated YAML files
uv run yamlfix tests/cloud_run_nl2sql_bq
```

## Factory-Specific Learnings & Gotchas

- **Multi-Regional Vertex AI (`GOOGLE_CLOUD_LOCATION` vs. `REGION`):**
  - The Cloud Run service uses `GOOGLE_CLOUD_LOCATION` (`var.multi_region`, e.g., `eu` or `us`) for Gemini model calls while keeping `REGION` (`var.region`, e.g., `europe-west1`) for regional resources.
  - Because Cloud Run uses `PRIVATE_RANGES_ONLY` VPC egress, [`0-prereqs/networking.tf`](./0-prereqs/networking.tf) provisions a regional PSC endpoint and DNS response policy rule for `aiplatform.<multi_region>.rep.googleapis.com`.
- **Container Lockfile (`uv.lock`):**
  - Whenever [`1-apps/apps/nl2sql/pyproject.toml`](./1-apps/apps/nl2sql/pyproject.toml) is updated, regenerate [`1-apps/apps/nl2sql/uv.lock`](./1-apps/apps/nl2sql/uv.lock) via `uv lock` so `uv sync --frozen` succeeds during Cloud Build.
