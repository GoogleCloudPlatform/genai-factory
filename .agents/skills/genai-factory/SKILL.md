---
name: genai-factory
description: Use when choosing, configuring, deploying, customizing, or troubleshooting any GoogleCloudPlatform/genai-factory Terraform blueprint on GCP—including Cloud Run GenAI apps (chat, ADK, A2A, Gemma on L4 GPU, FastMCP), RAG pipelines (Cloud SQL pgvector, AlloyDB ScaNN, Vector Search 2.0), NL2SQL on BigQuery, Vertex AI Agent Engine (PSC-I, Firestore), Vertex AI Search, Gemini Enterprise & Agent Platform (Agent Registry, Agent Gateway, Custom MCP, IAM v3 UAPs), CX Agent Studio, Dialogflow CX, or private Model Garden endpoints.
---

# GenAI Factory — Master Router Skill

## Overview

[`GoogleCloudPlatform/genai-factory`](https://github.com/GoogleCloudPlatform/genai-factory) provides two-stage (`0-prereqs` and `1-apps`), least-privilege Terraform blueprints built on [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) for deploying generative AI infrastructure on Google Cloud.

## When to Use

- Selecting a `genai-factory` blueprint for a GCP generative AI workload.
- Deploying or troubleshooting `0-prereqs` or `1-apps` for any factory below.
- **REQUIRED ACTION:** Always load the matching **Per-Factory Skill** (`<factory>/SKILL.md` locally or via its raw GitHub URL below) plus its required `genai-factory-*` shared skills before proposing Terraform or CLI commands.

## Quick Reference — Per-Factory Skills

| Factory | Use Case | Local Path | Remote `SKILL.md` |
| :--- | :--- | :--- | :--- |
| `agent-runtime` | Vertex AI Agent Engine (ADK & A2A), PSC-I, SWP, Firestore sessions | `agent-runtime/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/agent-runtime/SKILL.md) |
| `ai-apps-search` | Vertex AI Search (`PUBLIC_WEBSITE`, `SEARCH_TIER_ENTERPRISE`) | `ai-apps-search/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/ai-apps-search/SKILL.md) |
| `cloud-run-nl2sql-bq` | Cloud Run ADK NL2SQL agent querying BigQuery | `cloud-run-nl2sql-bq/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-nl2sql-bq/SKILL.md) |
| `cloud-run-rag-alloydb` | Cloud Run RAG + BigQuery job on AlloyDB (`pgvector` + `alloydb_scann` over PSC) | `cloud-run-rag-alloydb/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-rag-alloydb/SKILL.md) |
| `cloud-run-rag-cloudsql` | Cloud Run RAG + BigQuery job on Cloud SQL (`pgvector` `halfvec` over PSC) | `cloud-run-rag-cloudsql/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-rag-cloudsql/SKILL.md) |
| `cloud-run-rag-search` | Cloud Run RAG + GCS job on Vertex AI Vector Search 2.0 (Hybrid RRF) | `cloud-run-rag-search/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-rag-search/SKILL.md) |
| `cloud-run-single` | Single Cloud Run app (`chat`, `adk`, `adk-a2a`, `gemma` on L4 GPU, `mcp-server`) | `cloud-run-single/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/cloud-run-single/SKILL.md) |
| `ge-agent-platform` | Gemini Enterprise apps, SaaS/MCP connectors, Agent Registry & Gateway, IAM v3 UAPs | `ge-agent-platform/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/ge-agent-platform/SKILL.md) |
| `gecx-agent-studio` | CX Agent Studio (`google_ces_app`), Discovery Engine KB, private Service Directory toolsets | `gecx-agent-studio/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/gecx-agent-studio/SKILL.md) |
| `gecx-dialogflow` | Dialogflow CX agent, FAQ/KB data stores, private Service Directory webhooks | `gecx-dialogflow/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/gecx-dialogflow/SKILL.md) |
| `serve-private-models` | Vertex AI Model Garden open models (Gemma 3) over PSC to Cloud Run | `serve-private-models/SKILL.md` | [SKILL.md](https://raw.githubusercontent.com/GoogleCloudPlatform/genai-factory/master/serve-private-models/SKILL.md) |

## Quick Reference — Shared Sub-Skills

- **REQUIRED SUB-SKILL for Stage 0, BYO-VPC, FAST, or `*.rep.googleapis.com`:** [`genai-factory-prerequisites-and-fast`](../genai-factory-prerequisites-and-fast/SKILL.md)
- **REQUIRED SUB-SKILL for Cloud Run, External/Internal ALB, CAS, or RAG Jobs:** [`genai-factory-cloud-run-and-load-balancers`](../genai-factory-cloud-run-and-load-balancers/SKILL.md)
- **REQUIRED SUB-SKILL for Model Armor Templates & Floor Settings:** [`genai-factory-model-armor`](../genai-factory-model-armor/SKILL.md)
- **REQUIRED SUB-SKILL for Discovery Engine & GECX Service Directory TCP Proxy LBs:** [`genai-factory-discovery-engine-and-gecx`](../genai-factory-discovery-engine-and-gecx/SKILL.md)
- **REQUIRED SUB-SKILL for Impersonation Quota Fixes & Clean Teardown:** [`genai-factory-operations-and-teardown`](../genai-factory-operations-and-teardown/SKILL.md)
