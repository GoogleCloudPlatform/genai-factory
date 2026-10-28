---
name: genai-factory-gecx-dialogflow
description: Use when deploying or configuring the genai-factory gecx-dialogflow blueprint (Dialogflow CX Conversational Agent with Discovery Engine FAQ and unstructured knowledge base data stores, plus private Cloud Run Function and on-prem webhooks over Service Directory and Internal Regional TCP Proxy Load Balancers), or running agentutil.py to import documents, restore agents, and test detectIntent.
---

# GenAI Factory — GECX Dialogflow (`gecx-dialogflow`)

## Overview

Deploys a **Dialogflow CX Conversational Agent** ([`gecx-dialogflow`](./README.md)) backed by **Vertex AI Search (Discovery Engine)** structured FAQ (`faq`) and unstructured knowledge base (`kb`) data stores, plus private **2nd Gen Cloud Run Function** and **on-premises** webhooks exposed via **Service Directory** and **Internal Regional TCP Proxy Load Balancers**.

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `gecx-dialogflow`.
- Configuring `agent_configs` or `service_directory_configs`, or running [`1-apps/scripts/agentutil/agentutil.py`](./1-apps/scripts/agentutil/agentutil.py) to import FAQ/KB documents, restore the Dialogflow CX agent archive, register private webhooks, and test `detectIntent`.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO Shared VPC, and Fabric FAST.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-discovery-engine-and-gecx`](../.agents/skills/genai-factory-discovery-engine-and-gecx/SKILL.md) for `region_discovery_engine` (`eu`/`us`) vs. `region`, Service Directory + Internal Regional TCP Proxy LB architecture, and DER CA certificate requirements.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT`, Serverless VPC IP reservation delays, and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-gecx-df-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-gecx-df-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Default Name (`var.name`)** | `gecx-df-0` ([`1-apps/variables.tf`](./1-apps/variables.tf)) |
| **Required SA Keys (`1-apps`)** | `service-01/iac-rw` (deployer + `agentutil.py`), `service-01/gecx-df-0` (Cloud Function runtime SA), `service-01/gecx-df-build-0` (Cloud Function build SA) |
| **Service Agent IAM** | `service-01/dialogflow` SA: `servicedirectory.pscAuthorizedService` & `servicedirectory.viewer`; `service-01/certificatemanager` SA: `privateca.certificateRequester`; Host `iac-rw`: `compute.networkUser`, `dns.admin`, `servicedirectory.networkAttacher` |

## Core Patterns

### Customize Agent Variant & Service Directory Webhooks (`1-apps/terraform.tfvars`)

```hcl
region                  = "europe-west1"
region_discovery_engine = "eu" # Must be "eu" or "us"

agent_configs = {
  language = "en"
  variant  = "default" # Folder under 1-apps/data/agents/<variant>
}

service_directory_configs = {
  default = {
    cloud_dns_domain = "example.com"
    endpoints = {
      onprem-01 = { address = "192.168.0.100", port = 443, create_lb = true }
    }
    services = {
      onprem = { endpoints = ["onprem-01"] }
    }
  }
}
```

### Import Data Stores, Restore Agent & Test `detectIntent`

After `terraform apply` in `1-apps/`, run `terraform output -raw commands` ([`1-apps/templates/outputs.sh`](./1-apps/templates/outputs.sh)) to:

1. Upload `./data/ds-faq/faq.csv` to GCS and call `documents:import` (`dataSchema = "csv"`, `reconciliationMode = "FULL"`) on the `faq` data store.
2. Process `./data/ds-kb/` via `agentutil.py process-documents ... --upload` and call `documents:import` on the `kb` data store.
3. Package `./data/agents/<variant>/*`, run `agentutil.py replace-data-store`, upload `agent.dist.zip`, and call `agents:restore`.
4. Register private Service Directory webhooks (`agentutil.py create-webhook`).
5. Test `POST https://<region>-dialogflow.googleapis.com/v3/<agent_id>/environments/draft/sessions/any-session-id:detectIntent`.

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| `detectIntent` returns fallback/empty answers right after `documents:import` | Initial Discovery Engine indexing and 500-token layout chunking take 5–15 minutes | Wait for the import operation to complete in Cloud Console (AI Applications -> Data Stores) before testing KB intents. |
| `404` or region mismatch when calling Dialogflow CX or Discovery Engine REST APIs | Dialogflow CX uses `<region>-dialogflow.googleapis.com` (`europe-west1`) while Discovery Engine uses `<region_discovery_engine>-discoveryengine.googleapis.com` (`eu`/`us`) | Never mix the regional (`var.region`) and multi-regional (`var.region_discovery_engine`) hostname prefixes. |
