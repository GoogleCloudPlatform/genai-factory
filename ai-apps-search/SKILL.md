---
name: genai-factory-ai-apps-search
description: Use when deploying or configuring the genai-factory ai-apps-search blueprint (Vertex AI Search / Discovery Engine public website search engine), customizing target website URI patterns (target_sites), querying the servingConfigs/default_search:search API, or troubleshooting empty basic website search results.
---

# GenAI Factory — AI Apps Search (`ai-apps-search`)

## Overview

Deploys a **Vertex AI Search (Discovery Engine)** application ([`ai-apps-search`](./README.md)) indexing public website URI patterns (`PUBLIC_WEBSITE` content configuration) with an Enterprise-tier search engine (`SEARCH_TIER_ENTERPRISE`) via the Cloud Foundation Fabric `ai-applications` module.

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `ai-apps-search`.
- Customizing included/excluded website URI patterns (`ai_apps_configs.target_sites`) or querying the search engine.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`) project creation (`gf-ai-apps-srch-0`, no VPC required).
- **REQUIRED SUB-SKILL:** Load [`genai-factory-discovery-engine-and-gecx`](../.agents/skills/genai-factory-discovery-engine-and-gecx/SKILL.md) for Discovery Engine data store/engine conventions.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT` and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Service Project (`0-prereqs`)** | `gf-ai-apps-srch-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)) — no Host project or VPC required |
| **Default Name (`var.name`)** | `srch-0` (creates data store `srch-0-ds` and search engine `srch-0-app`) |
| **Required SA Key (`0-prereqs`)** | `service-01/iac-rw` (`roles/discoveryengine.admin`) |
| **Default Target Site** | `github.com/GoogleCloudPlatform/cloud-foundation-fabric/*` ([`1-apps/variables.tf`](./1-apps/variables.tf)) |

## Core Patterns

### Custom Included & Excluded Website URI Patterns (`1-apps/terraform.tfvars`)

```hcl
ai_apps_configs = {
  target_sites = {
    docs-main = {
      provided_uri_pattern = "docs.example.com/*"
      exact_match          = false
      type                 = "INCLUDE"
    }
    docs-legacy-exclude = {
      provided_uri_pattern = "docs.example.com/archive/*"
      exact_match          = false
      type                 = "EXCLUDE"
    }
  }
}
```

### Apply & Query the Search Engine

```shell
cd 1-apps
terraform init && terraform apply

# Prints POST .../servingConfigs/default_search:search curl command and Web Widget Console URL
terraform output -raw commands
```

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| Invalid `provided_uri_pattern` error during `terraform apply` | Included `https://` scheme prefix in `provided_uri_pattern` | Omit the scheme prefix and use `"domain.com/path/*"` format. |
| Search returns empty results right after `terraform apply` | Basic site search (`create_advanced_site_search = false`) relies on public Google Search index coverage for `provided_uri_pattern` | Verify the target site is indexed by Google Search, or enable `create_advanced_site_search = true` in [`1-apps/main.tf`](./1-apps/main.tf) with domain verification. |
| Need to index private PDFs/HTML/JSONL in GCS instead of public websites | `ai-apps-search` is pre-configured for `PUBLIC_WEBSITE` | Use [`genai-factory-gecx-dialogflow`](../gecx-dialogflow/SKILL.md), [`genai-factory-gecx-agent-studio`](../gecx-agent-studio/SKILL.md), or [`genai-factory-ge-agent-platform`](../ge-agent-platform/SKILL.md) for GCS-backed Discovery Engine data stores. |
