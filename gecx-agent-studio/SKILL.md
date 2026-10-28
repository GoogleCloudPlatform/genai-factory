---
name: genai-factory-gecx-agent-studio
description: Use when deploying or configuring the genai-factory gecx-agent-studio blueprint (Gemini Enterprise for Customer Experience / CX Agent Studio google_ces_app with Discovery Engine data stores and private Cloud Run or on-prem OpenAPI toolsets over Service Directory and Internal Regional TCP Proxy Load Balancers), or running agentutil.py to ingest documents, create toolsets, and push CES agents.
---

# GenAI Factory — GECX Agent Studio (`gecx-agent-studio`)

## Overview

Deploys a **Gemini Enterprise for Customer Experience (CX Agent Studio / `google_ces_app`)** application ([`gecx-agent-studio`](./README.md)) with **Discovery Engine** knowledge base data stores and private **Cloud Run** and **on-premises** OpenAPI toolsets reached privately over **Service Directory** and **Internal Regional TCP Proxy Load Balancers**.

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `gecx-agent-studio`.
- Configuring `agents_configs`, `datastores_configs`, or `service_directory_configs`, or running [`1-apps/scripts/agentutil.py`](./1-apps/scripts/agentutil.py) to ingest data stores, register private OpenAPI toolsets, and push the CES agent bundle.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO Shared VPC, and Fabric FAST.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-discovery-engine-and-gecx`](../.agents/skills/genai-factory-discovery-engine-and-gecx/SKILL.md) for `region_discovery_engine` (`eu`/`us`), Service Directory + Internal Regional TCP Proxy LB architecture, and DER CA certificate requirements.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT`, Serverless VPC IP reservation delays, and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-gecx-as-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-gecx-as-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Default Name (`var.name`)** | `cx-as-0` (creates CES app `cx-as-0`, datastore `cx-as-0-ds`, and private Cloud Run toolset `cx-as-0`) |
| **Required SA Keys (`1-apps`)** | `service-01/iac-rw` (deployer + `agentutil.py` SA), `service-01/gecx-as-0` (Cloud Run toolset runtime SA) |
| **Service Agent IAM** | Service `ces` SA: `servicedirectory.viewer` (service proj) & `servicedirectory.pscAuthorizedService` (host proj); Host `iac-rw`: `compute.networkUser`, `dns.admin`, `servicedirectory.networkAttacher` |
| **Extra `networking_config` Key** | `networking_config.host_project_number` is required in [`1-apps/variables.tf`](./1-apps/variables.tf) alongside `subnet` and `vpc` |

## Core Patterns

### Customize CES Apps, Data Stores & Private Toolsets (`1-apps/terraform.tfvars`)

```hcl
region_discovery_engine = "eu" # Must be "eu" or "us"

agents_configs = {
  cx-as-0 = {
    enable_cloud_logging        = true
    enable_conversation_logging = true
    supported_languages         = ["en-US", "it-IT"]
    timezone                    = "Europe/Rome"
    tool_execution_mode         = "PARALLEL"
    datastores                  = ["cx-as-0"]
  }
}

service_directory_configs = {
  example-com = {
    cloud_dns_domain = "example.com"
    endpoints = {
      "onprem/onprem-01" = { address = "10.0.0.2", port = 443, create_lb = true }
    }
    services = {
      onprem = { endpoints = ["onprem-01"], openapi_spec = "data/onprem/openapi-spec.yaml" }
    }
  }
}
```

### Ingest Data Stores, Wire Toolsets & Push CES Agent (`agentutil.py`)

After `terraform apply` in `1-apps/`, run `terraform output -raw commands` ([`1-apps/templates/outputs.sh`](./1-apps/templates/outputs.sh)) to:

1. Ingest `data/datastores/ds-kb/` into GCS and Discovery Engine (`agentutil.py data-store ingest`).
2. Stage `./data/apps/cx-as-0` into `./build/app/dist/cx-as-0/agent` and replace datastore placeholders (`agentutil.py ces agent replace-data-store`).
3. Register private OpenAPI toolsets (`agentutil.py create-toolset`) with base64-encoded DER CA certs (`data/cloud-run/cert.der`).
4. Push the CES agent bundle (`agentutil.py ces agent push`).

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| Terraform ignores subsequent edits to `google_ces_app` fields | `google_ces_app.gecx_as_app` sets `lifecycle { ignore_changes = [...] }` in [`1-apps/main.tf`](./1-apps/main.tf) by design | Use `uv run scripts/agentutil.py ces agent push` (or the CX Agent Studio UI) to update prompts, guardrails, datastores, and toolsets. |
| CES toolset calls fail TLS validation over Service Directory | `cert.der` is PEM-encoded instead of binary DER, or SAN/CN mismatches `<service_id>.<cert_common_name>` | Provide a binary **DER** certificate in `data/cloud-run/cert.der` whose SAN and `openapi-spec.yaml` `servers:` URL match the toolset hostname. |
