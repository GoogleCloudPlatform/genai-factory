# GenAI Factory Skills

This directory contains shared skills for AI coding agents working with the GenAI Factory repository, registered via [`../skills.json`](../skills.json).

Skills are organized into three categories:

1. **Per-Factory Skills (`../../<factory>/SKILL.md`)**: Located directly at the root of each factory folder, containing factory-specific identity tables, `terraform.tfvars` recipes, and application playbooks that link back to the shared skills below.
2. **Shared Factory Deployment & Operation Skills (`.agents/skills/<name>/SKILL.md`)**: Reusable runbooks for deploying, configuring, customizing, and tearing down `genai-factory` blueprints.
3. **Repository Maintenance Skills (`.agents/skills/maintain-*/SKILL.md`)**: Workflows for maintaining, testing, and releasing the `genai-factory` repository itself (always prefixed with `maintain-`).

______________________________________________________________________

## Per-Factory Skills

- **[agent-runtime](../../agent-runtime/SKILL.md)**: Deploying and operating Vertex AI Agent Engine runtimes with Google ADK and A2A agents, PSC-I private networking, Secure Web Proxy internet egress, and Firestore session/task persistence.
- **[ai-apps-search](../../ai-apps-search/SKILL.md)**: Deploying and operating a Vertex AI Search (Discovery Engine) public website search application and embeddable search widget.
- **[cloud-run-nl2sql-bq](../../cloud-run-nl2sql-bq/SKILL.md)**: Deploying and operating a Natural Language to SQL (NL2SQL) Google ADK agent on Cloud Run querying BigQuery behind an External or Internal Application Load Balancer.
- **[cloud-run-rag-alloydb](../../cloud-run-rag-alloydb/SKILL.md)**: Deploying and operating a Cloud Run RAG frontend and BigQuery ingestion job backed by AlloyDB for PostgreSQL (`pgvector` + `alloydb_scann`) over Private Service Connect.
- **[cloud-run-rag-cloudsql](../../cloud-run-rag-cloudsql/SKILL.md)**: Deploying and operating a Cloud Run RAG frontend and BigQuery ingestion job backed by Cloud SQL for PostgreSQL (`pgvector`) over Private Service Connect.
- **[cloud-run-rag-search](../../cloud-run-rag-search/SKILL.md)**: Deploying and operating a Cloud Run RAG frontend and GCS ingestion job backed by Vertex AI Vector Search 2.0 Collections (auto-embeddings + Hybrid Search / Reciprocal Rank Fusion).
- **[cloud-run-single](../../cloud-run-single/SKILL.md)**: Deploying and operating a single containerized GenAI application (`chat`, `adk`, `adk-a2a`, `gemma`, `mcp-server`) on Cloud Run.
- **[ge-agent-platform](../../ge-agent-platform/SKILL.md)**: Deploying and operating Gemini Enterprise applications/assistants, SaaS and Custom MCP data connectors (with OAuth 2.0), Agent Registry, Egress Agent Gateway, directional Model Armor templates, and IAM v3 Unified Access Policies.
- **[gecx-agent-studio](../../gecx-agent-studio/SKILL.md)**: Deploying and operating Gemini Enterprise for Customer Experience (CX Agent Studio) with Discovery Engine data stores and private Cloud Run / on-prem OpenAPI toolsets via Service Directory and Internal Regional TCP Proxy Load Balancers.
- **[gecx-dialogflow](../../gecx-dialogflow/SKILL.md)**: Deploying and operating a Dialogflow CX Conversational Agent with Discovery Engine FAQ/KB data stores and private Cloud Run Function / on-prem webhooks via Service Directory and Internal Regional TCP Proxy Load Balancers.
- **[serve-private-models](../../serve-private-models/SKILL.md)**: Deploying and operating Vertex AI Model Garden open models (such as Gemma 3) privately exposed via Private Service Connect to a Cloud Run application.

______________________________________________________________________

## Shared Factory Deployment & Operation Skills

- **[genai-factory](./genai-factory/SKILL.md)**: Master router and index skill for choosing, configuring, deploying, and troubleshooting any GenAI Factory blueprint.
- **[prerequisites-and-fast](./prerequisites-and-fast/SKILL.md)**: Configuring and deploying Stage 0 (`0-prereqs`), Bring Your Own Shared VPC (`networking_config.create = false`), Fabric FAST integration (`variables-fast.tf`), and `.rep.googleapis.com` regional PSC endpoints and Cloud DNS policies.
- **[cloud-run-and-load-balancers](./cloud-run-and-load-balancers/SKILL.md)**: Configuring Cloud Run services/jobs, External HTTPS GLB, Internal ALB + CAS (`ca_pool_name_suffix`), Direct Cloud Run ingress, Cloud Build container submissions, and Python GenAI/ADK conventions.
- **[model-armor](./model-armor/SKILL.md)**: Configuring regional Model Armor templates (`google_model_armor_template`), project floor settings (`google_model_armor_floorsetting`), filter confidence thresholds, and regional modality constraints.
- **[discovery-engine-and-gecx](./discovery-engine-and-gecx/SKILL.md)**: Provisioning Discovery Engine data stores (`document_processing_config`, service agent IAM) and private GECX fulfillment via Service Directory + Internal Regional TCP Proxy LB.
- **[operations-and-teardown](./operations-and-teardown/SKILL.md)**: Fixing `gcloud` service account impersonation quota project errors (`CLOUDSDK_BILLING_QUOTA_PROJECT`), diagnosing private `.rep.googleapis.com` timeouts, handling Serverless VPC IP reservation delays on destroy, and cleaning up Stage 0 generated files.

______________________________________________________________________

## Repository Maintenance Skills (`maintain-*`)

- **[maintain-release-process](./maintain-release-process/SKILL.md)**: Guide for cutting, verifying, and publishing a new GitHub release of the GenAI Factory repository.
