---
name: cloud-run-rag-alloydb
description: >-
  Actionable runbook for configuring, deploying, customizing, and operating the
  cloud-run-rag-alloydb factory (Cloud Run RAG frontend and scheduled BigQuery
  ingestion job backed by AlloyDB for PostgreSQL with pgvector and alloydb_scann
  over Private Service Connect). Use this skill whenever a user asks to deploy
  or configure cloud-run-rag-alloydb, build and run the BigQuery-to-AlloyDB
  embedding pipeline, configure 3072-dimension ScaNN vector indexes, or
  troubleshoot AlloyDB PSC and IAM authentication.
---

# Cloud Run RAG with AlloyDB (`cloud-run-rag-alloydb`) Skill

This skill provides the factory-specific specifications, configuration recipes, and application/ingestion playbook for deploying and operating the `cloud-run-rag-alloydb` blueprint.

> [!NOTE]
>
> - For shared prerequisite workflows (`0-prereqs`, BYO Shared VPC, Fabric FAST), load [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md).
> - For Load Balancer (`lbs_configs`), Cloud Armor, CAS (`ca_pool_name_suffix`), Direct Cloud Run access (`cloud_run_configs`), scheduled ingestion (`ingestion_schedule_configs`), and Python container build patterns, load [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).
> - For E2E troubleshooting and teardown, load [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md).
> - For repository contributor rules and test inventory regeneration, see [`AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Factory Identity & Stage 0 (`0-prereqs`) Specification

Follow the step-by-step workflows in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) (Standalone `0-prereqs`, Bring Your Own Shared VPC, or Fabric FAST) using these `cloud-run-rag-alloydb` identifiers:

| Component | Factory Value / Definition | Notes |
| :--- | :--- | :--- |
| **Service Project Name (`0-prereqs`)** | `gf-rrag-all-0` | Defined in [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml). |
| **Host Project Name** *(when `networking_config.create = true`)* | `gf-rrag-all-hp-0` | Defined in [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml). |
| **Default Stage 1 Resource Name (`var.name`)** | `gf-rrag-0` | Defined in [`1-apps/variables.tf`](./1-apps/variables.tf). AlloyDB cluster name is `alloydb`, primary instance name is `${var.name}`, and BigQuery dataset/table ID is `gf_rrag_0`. |
| **Required Project Number (`var.number`)** | Service project number | Required in [`1-apps/variables.tf`](./1-apps/variables.tf) to authorize the service project in AlloyDB's `psc_config.allowed_consumer_projects` ([`1-apps/database.tf`](./1-apps/database.tf)). Automatically populated by `0-prereqs` in `terraform.auto.tfvars`. |
| **Required `service_account_emails` & `service_account_ids` Keys** | `service-01/iac-rw`<br>`service-01/gf-rrag-fe-0`<br>`service-01/gf-rrag-fe-build-0`<br>`service-01/gf-rrag-ing-0`<br>`service-01/gf-rrag-ing-build-0`<br>`service-01/gf-rrag-ing-sched-0` | Stage 1 automation SA (`iac-rw`), Frontend runtime & build SAs (`gf-rrag-fe-*`), Ingestion job runtime & build SAs (`gf-rrag-ing-*`), and Cloud Scheduler trigger SA (`gf-rrag-ing-sched-0`). |
| **Host Project IAM** *(critical for BYO Shared VPC / FAST)* | `roles/compute.networkUser` & `roles/dns.admin` for `service-01/iac-rw`<br>`roles/compute.networkUser` for `service-01/run` service agent | `service-01/iac-rw` creates the AlloyDB PSC consumer IP/forwarding rule (`psc_consumer_fwd_rule`) and binds the private Cloud DNS zone (`${var.name}-alloydb`) to the Shared VPC ([`1-apps/database.tf`](./1-apps/database.tf)). |
| **Regional PSC Endpoints (`0-prereqs/networking.tf`)** | `aiplatform.<eu\|us>.rep.googleapis.com` | Defined in [`0-prereqs/networking.tf`](./0-prereqs/networking.tf). Required for multi-regional Gemini and embedding calls over private VPC egress. |

______________________________________________________________________

## 2. Stage 1 (`1-apps`) Architecture & Configuration (`terraform.tfvars`)

Stage 1 variables are declared in [`1-apps/variables.tf`](./1-apps/variables.tf) (and [`1-apps/variables-fast.tf`](./1-apps/variables-fast.tf) for FAST integration).

- **AlloyDB PSC & IAM Setup ([`1-apps/database.tf`](./1-apps/database.tf))**:
  - Provisions an AlloyDB cluster (`alloydb`) and primary instance (`${var.name}`) with `alloydb.iam_authentication = "on"` and Private Service Connect (`psc_config`) enabled.
  - Registers `gf-rrag-fe-0` (`alloydbiamuser`) and `gf-rrag-ing-0` (`alloydbiamuser`, `alloydbsuperuser`) as `ALLOYDB_IAM_USER` database users (with the `.gserviceaccount.com` suffix trimmed).
  - Creates an internal PSC consumer IP, a PSC forwarding rule (`allow_psc_global_access = true`), and a private Cloud DNS zone for `module.alloydb.psc_dns_name`.
- **Exposure Layer & Scheduled Ingestion (`lbs_configs`, `ca_pool_name_suffix`, `cloud_run_configs`, `ingestion_schedule_configs`)**:
  - Supports **External HTTPS Load Balancer** ([`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), enabled by default), **Internal Application Load Balancer + CAS** ([`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/lb-int-cert.tf`](./1-apps/lb-int-cert.tf)), or **Direct Cloud Run Access** on `cloud_run_configs.frontend` (`INGRESS_TRAFFIC_ALL`), plus Cloud Scheduler tuning via `ingestion_schedule_configs`.
  - Use the recipes in [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md).

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
   - **What the ingestion job does** ([`ingestion/src/db.py`](./1-apps/apps/rag/ingestion/src/db.py)): Connects to AlloyDB over PSC (`Connector(ip_type="PSC")` with `enable_iam_auth=True`), creates database `${DB_NAME}` if it does not exist, enables the `vector` extension, creates table `${DB_TABLE}`, reads rows from BigQuery, generates `3072`-dimension `gemini-embedding-001` vectors in batches (`BATCH_SIZE_EMBEDDING = 25`), and upserts them.
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

1. **`3072`-Dimension Vectors & AlloyDB `scann` Index (`alloydb_scann`)**:
   - `gemini-embedding-001` produces `3072`-dimension vectors (`vector(3072)`). While standard `pgvector` `ivfflat` and `hnsw` indexes cap `vector` columns at `2000` dimensions, AlloyDB's `scann` index (`CREATE EXTENSION IF NOT EXISTS alloydb_scann; CREATE INDEX ... USING scann (embedding cosine) ...`) natively supports `3072`-dimension vectors.
2. **AlloyDB Instance URI Convention**:
   - Both [`frontend/src/config.py`](./1-apps/apps/rag/frontend/src/config.py) and [`ingestion/src/config.py`](./1-apps/apps/rag/ingestion/src/config.py) construct `ALLOYDB_INSTANCE_URI = f"projects/{PROJECT_ID}/locations/{REGION}/clusters/alloydb/instances/{DB_NAME}"`. If you change `cluster_name` or `instance_name` in [`1-apps/database.tf`](./1-apps/database.tf), update `ALLOYDB_INSTANCE_URI` accordingly.
3. **Always Pass `--container=frontend` / `--container=ingestion` on Deploy**:
   - Both [`1-apps/frontend.tf`](./1-apps/frontend.tf) and [`1-apps/ingestion.tf`](./1-apps/ingestion.tf) define an `alloydb-proxy` sidecar container (`gcr.io/alloydb-connectors/alloydb-auth-proxy`). Always include `--container=frontend` or `--container=ingestion` when running `gcloud run deploy` or `gcloud run jobs deploy`.
4. **Two Separate `uv.lock` Files**:
   - [`1-apps/apps/rag/frontend/`](./1-apps/apps/rag/frontend) and [`1-apps/apps/rag/ingestion/`](./1-apps/apps/rag/ingestion) maintain independent `pyproject.toml` and `uv.lock` files. Run `uv lock` in the modified subfolder before building containers.
