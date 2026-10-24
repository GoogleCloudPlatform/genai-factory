---
name: ai-apps-search
description: Actionable runbook for configuring, deploying, customizing, and operating the ai-apps-search factory (Vertex AI Search / Discovery Engine public website search application). Use this skill whenever a user asks to deploy or configure ai-apps-search, customize target website URI patterns in Discovery Engine, query the Vertex AI Search servingConfig API, or embed the search widget.
---

# AI Apps Search — Deployment & Operations Runbook

This skill guides you through configuring, deploying, customizing, and troubleshooting the [`ai-apps-search`](./README.md) factory: a **Vertex AI Search (Discovery Engine)** application indexing public website URI patterns (`PUBLIC_WEBSITE` content configuration) with an Enterprise-tier search engine (`SEARCH_TIER_ENTERPRISE`), deployed via the Cloud Foundation Fabric `ai-applications` module.

> [!NOTE]
> For repository contributor workflows (regenerating `plan_summary.py` test inventories and running `pytest`), also consult [`ai-apps-search/AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Shared Skills Reference (Do Not Duplicate)

This factory relies on the repository's shared skills in [`../.agents/skills/`](../.agents/skills/README.md) for cross-cutting workflows. Always load the relevant shared skill first:

| Workflow Area | Shared Skill | How `ai-apps-search` Uses It |
| :--- | :--- | :--- |
| **Stage 0 (`0-prereqs`) & Custom Project Setup** | [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) | Deploys the single service project (`gf-ai-apps-srch-0`) and Terraform state bucket (no Shared VPC host project is required). |
| **Discovery Engine Data Stores & Search API** | [`discovery-engine-and-gecx`](../.agents/skills/discovery-engine-and-gecx/SKILL.md) | Covers Discovery Engine data store / engine architecture and multi-region / regional API concepts. |
| **Impersonation Quota Fixes & Clean Teardown** | [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md) | Resolves `403 serviceusage.services.use` and cleans up generated `1-apps` files (`providers.tf`, `terraform.auto.tfvars`). |

______________________________________________________________________

## 2. Factory-Specific Resource & Identity Identifiers

When applying the patterns in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md), use these exact `ai-apps-search` identifiers:

- **Default Resource Name (`var.name` in `1-apps`):** `"srch-0"` (creates data store `srch-0-ds` and search engine `srch-0-app`).
- **Stage 0 Project YAML Template:**
  - Service project (`gf-ai-apps-srch-0`): [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - Note: `ai-apps-search` does **not** create a Host project or VPC because Vertex AI Search is a fully managed Google API service.
- **Required Service Account in `0-prereqs`:**
  - `service-01/iac-rw` — Stage 1 Terraform deployer SA (`<prefix>-gf-ai-apps-srch-0-rw@...`, holds `roles/discoveryengine.admin`).

______________________________________________________________________

## 3. Step-by-Step Deployment Workflow

### Step 1: Run Stage 0 (`0-prereqs`)

In [`0-prereqs/`](./0-prereqs/README.md), create `terraform.tfvars` (`billing_account`, `parent`, `prefix`, `region`) and run `terraform init && terraform apply`. This generates `1-apps/providers.tf` and `1-apps/terraform.auto.tfvars`.

### Step 2: Configure Stage 1 (`1-apps/terraform.tfvars`)

#### Recipe A: Default Target Site (`github.com/GoogleCloudPlatform/cloud-foundation-fabric/*`)

No overrides are needed; [`1-apps/variables.tf`](./1-apps/variables.tf) defaults `ai_apps_configs.target_sites` to index `github.com/GoogleCloudPlatform/cloud-foundation-fabric/*`.

#### Recipe B: Custom Included & Excluded Website URI Patterns

Override `ai_apps_configs.target_sites` in `1-apps/terraform.tfvars`:

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

> [!IMPORTANT]
> **URI Pattern Format (`provided_uri_pattern`):**
> Do **not** include the `https://` scheme prefix in `provided_uri_pattern` unless required by specific Discovery Engine target site rules; follow the format `"domain.com/path/*"`.

### Step 3: Apply Stage 1 (`1-apps`)

```shell
cd 1-apps
terraform init
terraform apply
```

### Step 4: Query the Search Engine

View and run the generated `curl` search command:

```shell
terraform output -raw commands
```

As defined in [`1-apps/outputs.tf`](./1-apps/outputs.tf), this sends a `POST` request to `https://discoveryengine.googleapis.com/v1/<search_engine_name>/servingConfigs/default_search:search` with automatic query expansion and spell correction enabled, and prints the Google Cloud Console URL for the embeddable Web Widget (`https://console.cloud.google.com/gen-app-builder/locations/global/engines/<name>-app/integration/widget?project=<project_id>`).

______________________________________________________________________

## 4. Factory-Specific Troubleshooting (`ai-apps-search`)

### 1. Empty Search Results Immediately After `terraform apply`

- **Cause:** Basic website search (`create_advanced_site_search = false`) relies on Google Search index coverage for the target URI patterns (`provided_uri_pattern`). If a site or sub-path is newly published or not indexed by Google Search, or if you need live crawling/sitemap indexing of private or unindexed pages, basic site search may return empty results.
- **Fix:** Verify the URI pattern is publicly indexed, or customize [`1-apps/main.tf`](./1-apps/main.tf) to enable Advanced Site Search (`create_advanced_site_search = true`) and domain verification in the Discovery Engine console.

### 2. Switching to GCS Unstructured Document Search

- If you want to index PDFs/HTML/JSONL stored in Google Cloud Storage instead of public websites, inspect the Cloud Foundation Fabric [`ai-applications` module variables](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/master/modules/ai-applications/variables.tf) or see [`ge-agent-platform`](../ge-agent-platform/SKILL.md) and [`gecx-dialogflow`](../gecx-dialogflow/SKILL.md) for GCS-backed Discovery Engine data store patterns.
