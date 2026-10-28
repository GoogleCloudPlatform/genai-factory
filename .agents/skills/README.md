# GenAI Factory Skills

This directory contains shared skills for AI coding agents working with the GenAI Factory repository, registered via [`../skills.json`](../skills.json) and exported to [`agents-cli`](https://google.github.io/agents-cli/guide/extensions/) via [`../../agents-cli-extension.yaml`](../../agents-cli-extension.yaml).

Skills are organized into three categories:

1. **Per-Factory Skills (`../../<factory>/SKILL.md`)**: Located at the root of each factory folder, containing factory-specific identity tables, `terraform.tfvars` patterns, and application deployment steps that reference the shared skills below.
2. **Shared Factory Deployment & Operation Skills (`.agents/skills/genai-factory*/SKILL.md`)**: Reusable guides for deploying, configuring, customizing, and tearing down `genai-factory` blueprints.
3. **Repository Maintenance Skills (`.agents/skills/maintain-*/SKILL.md`)**: Workflows for maintaining, testing, and releasing the `genai-factory` repository itself (prefixed with `maintain-`).

______________________________________________________________________

## Per-Factory Skills

- **[genai-factory-agent-runtime](../../agent-runtime/SKILL.md)**: Vertex AI Agent Engine runtimes with Google ADK and A2A agents, PSC-I private networking, Secure Web Proxy internet egress, and Firestore session/task persistence.
- **[genai-factory-ai-apps-search](../../ai-apps-search/SKILL.md)**: Vertex AI Search (Discovery Engine) public website search application and embeddable search widget.
- **[genai-factory-cloud-run-nl2sql-bq](../../cloud-run-nl2sql-bq/SKILL.md)**: Natural Language to SQL (NL2SQL) Google ADK agent on Cloud Run querying BigQuery behind an External or Internal Application Load Balancer.
- **[genai-factory-cloud-run-rag-alloydb](../../cloud-run-rag-alloydb/SKILL.md)**: Cloud Run RAG frontend and BigQuery ingestion job backed by AlloyDB for PostgreSQL (`pgvector` + `alloydb_scann`) over Private Service Connect.
- **[genai-factory-cloud-run-rag-cloudsql](../../cloud-run-rag-cloudsql/SKILL.md)**: Cloud Run RAG frontend and BigQuery ingestion job backed by Cloud SQL for PostgreSQL (`pgvector`) over Private Service Connect.
- **[genai-factory-cloud-run-rag-search](../../cloud-run-rag-search/SKILL.md)**: Cloud Run RAG frontend and GCS ingestion job backed by Vertex AI Vector Search 2.0 Collections (auto-embeddings + Hybrid Search / Reciprocal Rank Fusion).
- **[genai-factory-cloud-run-single](../../cloud-run-single/SKILL.md)**: Single containerized GenAI application (`chat`, `adk`, `adk-a2a`, `gemma`, `mcp-server`) on Cloud Run.
- **[genai-factory-ge-agent-platform](../../ge-agent-platform/SKILL.md)**: Gemini Enterprise applications/assistants, SaaS and Custom MCP data connectors (with OAuth 2.0), Agent Registry, Egress Agent Gateway, directional Model Armor templates, and IAM v3 Unified Access Policies.
- **[genai-factory-gecx-agent-studio](../../gecx-agent-studio/SKILL.md)**: Gemini Enterprise for Customer Experience (CX Agent Studio) with Discovery Engine data stores and private Cloud Run / on-prem OpenAPI toolsets via Service Directory and Internal Regional TCP Proxy Load Balancers.
- **[genai-factory-gecx-dialogflow](../../gecx-dialogflow/SKILL.md)**: Dialogflow CX Conversational Agent with Discovery Engine FAQ/KB data stores and private Cloud Run Function / on-prem webhooks via Service Directory and Internal Regional TCP Proxy Load Balancers.
- **[genai-factory-serve-private-models](../../serve-private-models/SKILL.md)**: Vertex AI Model Garden open models (such as Gemma 3) privately exposed via Private Service Connect to a Cloud Run application.

______________________________________________________________________

## Shared Factory Deployment & Operation Skills

- **[genai-factory](./genai-factory/SKILL.md)**: Master router and index skill for choosing, configuring, deploying, and troubleshooting any GenAI Factory blueprint.
- **[genai-factory-prerequisites-and-fast](./genai-factory-prerequisites-and-fast/SKILL.md)**: Configuring and deploying Stage 0 (`0-prereqs`), Bring Your Own Shared VPC (`networking_config.create = false`), Fabric FAST integration (`variables-fast.tf`), and `.rep.googleapis.com` regional PSC endpoints and Cloud DNS policies.
- **[genai-factory-cloud-run-and-load-balancers](./genai-factory-cloud-run-and-load-balancers/SKILL.md)**: Configuring Cloud Run services/jobs, External HTTPS GLB, Internal ALB + CAS (`ca_pool_name_suffix`), Direct Cloud Run ingress, Cloud Build container submissions, and Python GenAI/ADK conventions.
- **[genai-factory-model-armor](./genai-factory-model-armor/SKILL.md)**: Configuring regional Model Armor templates (`google_model_armor_template`), project floor settings (`google_model_armor_floorsetting`), filter confidence thresholds, and regional modality constraints.
- **[genai-factory-discovery-engine-and-gecx](./genai-factory-discovery-engine-and-gecx/SKILL.md)**: Provisioning Discovery Engine data stores (`document_processing_config`, service agent IAM) and private GECX fulfillment via Service Directory + Internal Regional TCP Proxy LB.
- **[genai-factory-operations-and-teardown](./genai-factory-operations-and-teardown/SKILL.md)**: Fixing `gcloud` service account impersonation quota project errors (`CLOUDSDK_BILLING_QUOTA_PROJECT`), diagnosing private `.rep.googleapis.com` timeouts, handling Serverless VPC IP reservation delays on destroy, and cleaning up Stage 0 generated files.

______________________________________________________________________

## Repository Maintenance Skills (`maintain-*`)

- **[maintain-release-process](./maintain-release-process/SKILL.md)**: Cutting, verifying, and publishing a new GitHub release of the GenAI Factory repository.
