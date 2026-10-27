---
name: genai-factory
description: Master index and router skill for GoogleCloudPlatform/genai-factory (end-to-end Terraform blueprints for deploying secure generative AI infrastructure on Google Cloud). Use this skill whenever a user asks to choose, configure, deploy, customize, or troubleshoot any genai-factory blueprint on GCP—including Cloud Run GenAI apps (chat, ADK, A2A, Gemma on L4 GPU, FastMCP), RAG pipelines (Cloud SQL pgvector, AlloyDB ScaNN, Vertex AI Vector Search 2.0), NL2SQL on BigQuery, Vertex AI Agent Engine runtimes (PSC-I, Firestore sessions), Vertex AI Search (Discovery Engine), Gemini Enterprise & Agent Platform (Agent Registry, Agent Gateway, Custom MCP connectors, IAM v3 UAPs), CX Agent Studio, Dialogflow CX, or private Model Garden endpoints over PSC.
---

# GenAI Factory (`GoogleCloudPlatform/genai-factory`) — Master Router Skill

[`GoogleCloudPlatform/genai-factory`](https://github.com/GoogleCloudPlatform/genai-factory) is a collection of production-grade, least-privilege **Terraform blueprints** (built on [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) and compatible with Fabric FAST) for deploying generative AI infrastructure and sample applications on Google Cloud.

Each blueprint ("factory") is split into two stages:

- **`0-prereqs`**: Bootstraps the GCP service project (and optional Shared VPC host project), Terraform state buckets, least-privilege service accounts (`iac-rw`, runtime SAs), API enablement, and private networking (including regional PSC endpoints and Cloud DNS policies for `*.rep.googleapis.com`).
- **`1-apps`**: Deploys the GenAI platform infrastructure via Terraform (impersonating `iac-rw`) and outputs ready-to-run `gcloud` / `curl` / `uv` commands to deploy and test sample applications on top.

______________________________________________________________________

## How to Use This Router Skill

To avoid duplicating runbooks across repositories, the authoritative skills live directly inside [`GoogleCloudPlatform/genai-factory`](https://github.com/GoogleCloudPlatform/genai-factory). Whenever this skill is activated, follow these steps:

1. **Locate or Clone the Repository:**

   - Check if `genai-factory` is already present in the current workspace or local disk.
   - If the user wants to deploy or inspect a factory and does not have a local checkout yet, clone it (or ask where they want it cloned):
     ```shell
     git clone https://github.com/GoogleCloudPlatform/genai-factory.git
     cd genai-factory
     ```

2. **Load the Target Factory's `SKILL.md` and Shared Skills:**

   - Identify the target factory from **Section 1** below and read its `<factory>/SKILL.md` file (either from the local checkout or from `https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/<factory>/SKILL.md`).
   - Also load the relevant **Shared Deployment & Operation Skills** from **Section 2** below (`.agents/skills/<skill-name>/SKILL.md`) that the factory `SKILL.md` references.

______________________________________________________________________

## 1. Per-Factory Skills Index

Pick the factory that matches the user's architecture or product requirement, then load its `SKILL.md`:

| Factory | Use Case & Architecture Summary | Local Path (in repo) | Remote Raw `SKILL.md` URL |
| :--- | :--- | :--- | :--- |
| **`agent-runtime`** | **Vertex AI Agent Engine** runtime deploying Google ADK and ADK+A2A agents with Private Service Connect Interface (PSC-I), Secure Web Proxy internet egress, and Firestore session/artifact/memory/task persistence. | `agent-runtime/SKILL.md` | [agent-runtime/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/agent-runtime/SKILL.md) |
| **`ai-apps-search`** | **Vertex AI Search (Discovery Engine)** public website search application (`PUBLIC_WEBSITE`, `SEARCH_TIER_ENTERPRISE`) and embeddable web widget. | `ai-apps-search/SKILL.md` | [ai-apps-search/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/ai-apps-search/SKILL.md) |
| **`cloud-run-nl2sql-bq`** | **Cloud Run NL2SQL ADK Agent** translating natural language to BigQuery SQL behind an External or Internal Application Load Balancer. | `cloud-run-nl2sql-bq/SKILL.md` | [cloud-run-nl2sql-bq/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-nl2sql-bq/SKILL.md) |
| **`cloud-run-rag-alloydb`** | **Cloud Run RAG Frontend & Scheduled Ingestion Job** backed by **AlloyDB for PostgreSQL** (`pgvector` + `alloydb_scann` 3072-dim index) over PSC and BigQuery source tables. | `cloud-run-rag-alloydb/SKILL.md` | [cloud-run-rag-alloydb/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-rag-alloydb/SKILL.md) |
| **`cloud-run-rag-cloudsql`** | **Cloud Run RAG Frontend & Scheduled Ingestion Job** backed by **Cloud SQL for PostgreSQL** (`pgvector` 3072-dim `halfvec` HNSW index) over PSC and BigQuery source tables. | `cloud-run-rag-cloudsql/SKILL.md` | [cloud-run-rag-cloudsql/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-rag-cloudsql/SKILL.md) |
| **`cloud-run-rag-search`** | **Cloud Run RAG Frontend & Scheduled Ingestion Job** backed by **Vertex AI Vector Search 2.0 Collections** (auto-embeddings with `gemini-embedding-001` + Hybrid Search / RRF) and GCS. | `cloud-run-rag-search/SKILL.md` | [cloud-run-rag-search/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-rag-search/SKILL.md) |
| **`cloud-run-single`** | **Single Cloud Run GenAI Application** (`chat`, `adk`, `adk-a2a`, GPU-backed `gemma` on NVIDIA L4, or `mcp-server`) with External/Internal ALB, Cloud Armor, and Model Armor. | `cloud-run-single/SKILL.md` | [cloud-run-single/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-single/SKILL.md) |
| **`ge-agent-platform`** | **Gemini Enterprise & Agent Platform**: Gemini Enterprise apps/assistants, 1P/3P SaaS data connectors, location IdP/ACLs, Agent Registry, Custom MCP OAuth 2.0 connectors, Egress Agent Gateway, directional Model Armor, and IAM v3 Unified Access Policies. | `ge-agent-platform/SKILL.md` | [ge-agent-platform/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/ge-agent-platform/SKILL.md) |
| **`gecx-agent-studio`** | **Gemini Enterprise for Customer Experience (CX Agent Studio / `google_ces_app`)** with Discovery Engine data stores and private Cloud Run / on-prem OpenAPI toolsets via Service Directory & Internal Regional TCP Proxy LB. | `gecx-agent-studio/SKILL.md` | [gecx-agent-studio/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/gecx-agent-studio/SKILL.md) |
| **`gecx-dialogflow`** | **Dialogflow CX Conversational Agent** with Discovery Engine structured FAQ and unstructured KB data stores, plus private Cloud Run Function / on-prem webhooks via Service Directory & Internal Regional TCP Proxy LB. | `gecx-dialogflow/SKILL.md` | [gecx-dialogflow/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/gecx-dialogflow/SKILL.md) |
| **`serve-private-models`** | **Vertex AI Model Garden Open Models** (e.g., Gemma 3 on L4 GPU) privately exposed via Private Service Connect (PSC) to a Cloud Run chat frontend with ALB, Cloud Armor, and Model Armor. | `serve-private-models/SKILL.md` | [serve-private-models/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/serve-private-models/SKILL.md) |

______________________________________________________________________

## 2. Shared Deployment & Operation Skills Index

Every per-factory `SKILL.md` delegates cross-cutting workflows to these 5 shared skills under `.agents/skills/`:

| Shared Skill | Cross-Cutting Workflow Covered | Local Path (in repo) | Remote Raw `SKILL.md` URL |
| :--- | :--- | :--- | :--- |
| **`prerequisites-and-fast`** | Deploying Stage 0 (`0-prereqs`), Bring Your Own Shared VPC (`networking_config.create = false`), integrating `1-apps` with Cloud Foundation Fabric FAST (`variables-fast.tf`), and provisioning regional PSC endpoints + Cloud DNS response policies for `*.rep.googleapis.com`. | `.agents/skills/prerequisites-and-fast/SKILL.md` | [prerequisites-and-fast/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/.agents/skills/prerequisites-and-fast/SKILL.md) |
| **`cloud-run-and-load-balancers`** | Configuring External HTTPS GLB, Internal ALB + Certificate Authority Service (`ca_pool_name_suffix`), Cloud Armor IP allowlists, Direct Cloud Run ingress, Cloud Build container submissions, scheduled RAG ingestion jobs (`cloud_run_job_config`), and Python `google-genai`/`google-adk` conventions. | `.agents/skills/cloud-run-and-load-balancers/SKILL.md` | [cloud-run-and-load-balancers/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/.agents/skills/cloud-run-and-load-balancers/SKILL.md) |
| **`model-armor`** | Configuring regional Model Armor templates (`google_model_armor_template`), project floor settings (`google_model_armor_floorsetting`), SDP/PI/RAI filter confidence thresholds, enforcement modes, and regional modality constraints. | `.agents/skills/model-armor/SKILL.md` | [model-armor/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/.agents/skills/model-armor/SKILL.md) |
| **`discovery-engine-and-gecx`** | Provisioning Discovery Engine data stores (`eu`/`us` multi-region vs. regional locations, `document_processing_config`), and wiring private GECX fulfillment via Service Directory + Internal Regional TCP Proxy Load Balancers with DER CA certificates. | `.agents/skills/discovery-engine-and-gecx/SKILL.md` | [discovery-engine-and-gecx/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/.agents/skills/discovery-engine-and-gecx/SKILL.md) |
| **`operations-and-teardown`** | Fixing `gcloud` impersonation quota errors (`export CLOUDSDK_BILLING_QUOTA_PROJECT=<service-project-id>`), diagnosing `*.rep.googleapis.com` timeouts from private VPCs, handling Serverless VPC IP reservation delays on `terraform destroy`, and cleaning up Stage 0 generated files. | `.agents/skills/operations-and-teardown/SKILL.md` | [operations-and-teardown/SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/.agents/skills/operations-and-teardown/SKILL.md) |
