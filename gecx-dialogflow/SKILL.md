---
name: gecx-dialogflow
description: Actionable runbook for configuring, deploying, customizing, and operating the gecx-dialogflow factory (Dialogflow CX Conversational Agent with Discovery Engine FAQ and unstructured knowledge base data stores, plus private Cloud Run Function and on-prem webhooks via Service Directory and Internal Regional TCP Proxy Load Balancers). Use this skill whenever a user asks to deploy or configure gecx-dialogflow, import FAQ CSV or unstructured PDF/HTML documents into Dialogflow CX data stores, wire private webhooks over Service Directory, or restore/query Dialogflow CX agents with agentutil.py.
---

# GECX Dialogflow — Deployment & Operations Runbook

This skill guides you through configuring, deploying, customizing, and troubleshooting the [`gecx-dialogflow`](./README.md) factory: a **Dialogflow CX Conversational Agent** backed by **Vertex AI Search (Discovery Engine)** structured FAQ (`faq`) and unstructured knowledge base (`kb`) data stores, plus optional private **Cloud Run Function (2nd Gen)** and **on-premises** webhooks exposed via **Service Directory** and **Internal Regional TCP Proxy Load Balancers**.

> [!NOTE]
> For repository contributor workflows (regenerating `plan_summary.py` test inventories and running `pytest`), also consult [`gecx-dialogflow/AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Shared Skills Reference (Do Not Duplicate)

This factory relies on the repository's shared skills in [`../.agents/skills/`](../.agents/skills/README.md) for cross-cutting workflows. Always load the relevant shared skill first:

| Workflow Area | Shared Skill | How `gecx-dialogflow` Uses It |
| :--- | :--- | :--- |
| **Stage 0 (`0-prereqs`), BYO-VPC, Fabric FAST** | [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) | Deploys Host (`gf-gecx-df-hp-0`) & Service (`gf-gecx-df-0`) projects, Shared VPC, and Service Directory / Cloud DNS host project bindings. |
| **Discovery Engine Data Stores & Private Service Directory + Internal TCP Proxy LB Architecture** | [`discovery-engine-and-gecx`](../.agents/skills/discovery-engine-and-gecx/SKILL.md) | Explains `region_discovery_engine` (`eu`/`us`) vs. `region`, `service_directory_configs`, Internal Regional TCP Proxy LB + DER certificate requirements, and `agentutil.py` workflows. |
| **Impersonation Quota Fixes, Networking Debugging & Clean Teardown** | [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md) | Resolves `403 serviceusage.services.use`, Serverless VPC IP reservation teardown delays, and cleans up generated `1-apps` files. |

______________________________________________________________________

## 2. Factory-Specific Resource & Identity Identifiers

When applying the patterns in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) and [`discovery-engine-and-gecx`](../.agents/skills/discovery-engine-and-gecx/SKILL.md), use these exact `gecx-dialogflow` identifiers:

- **Default Resource Name (`var.name` in `1-apps`):** `"gecx-df-0"`
- **Stage 0 Project YAML Templates:**
  - Service project (`gf-gecx-df-0`): [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml) (enables `dialogflow.googleapis.com`, `discoveryengine.googleapis.com`, `cloudfunctions.googleapis.com`, `run.googleapis.com`, `privateca.googleapis.com`, `certificatemanager.googleapis.com`, `servicedirectory.googleapis.com`, `dns.googleapis.com`).
  - Host project (`gf-gecx-df-hp-0`): [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml).
- **Required `service_account_emails` / `service_account_ids` Map Keys in `1-apps`:**
  - `"service-01/iac-rw"` — Stage 1 Terraform & `agentutil.py` deployer SA (`<prefix>-gf-gecx-df-0-rw@...`, holds `roles/dialogflow.admin`, `roles/discoveryengine.admin`, `roles/cloudfunctions.admin`, `roles/servicedirectory.admin`, `roles/dns.admin`, `roles/compute.loadBalancerAdmin`, `roles/certificatemanager.owner`, `roles/privateca.admin`, `roles/storage.admin`).
  - `"service-01/gecx-df-0"` — Cloud Run Function runtime SA (`<prefix>-gf-gecx-df-0-cf@...`).
  - `"service-01/gecx-df-build-0"` — Cloud Run Function build SA (`<prefix>-gf-gecx-df-0-cfb@...`).
- **Required Service Agent IAM Bindings:**
  - **Service project (`service-01.yaml`):**
    - Dialogflow service agent (`service-01/dialogflow`): `roles/servicedirectory.pscAuthorizedService` and `roles/servicedirectory.viewer`
    - Certificate Manager service agent (`service-01/certificatemanager`): `roles/privateca.certificateRequester`
  - **Host project (`host.yaml`):**
    - Deployer SA (`service-01/iac-rw`): `roles/compute.networkUser`, `roles/dns.admin`, `roles/servicedirectory.networkAttacher`
    - Cloud Run service agent (`service-01/run`): `roles/compute.networkUser`

______________________________________________________________________

## 3. Step-by-Step Deployment Workflow

### Step 1: Run Stage 0 (`0-prereqs`)

Follow [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) in [`0-prereqs/`](./0-prereqs/README.md).

### Step 2: Configure Stage 1 (`1-apps/terraform.tfvars`)

In [`1-apps/`](./1-apps/README.md), consult [`discovery-engine-and-gecx`](../.agents/skills/discovery-engine-and-gecx/SKILL.md) and customize `1-apps/terraform.tfvars` using the recipes below.

#### Recipe A: Default Deployment (Dialogflow CX Agent, FAQ + KB Data Stores, Private Cloud Function & On-Prem Webhooks)

No overrides are required beyond `terraform.auto.tfvars` generated by Stage 0:

- Provisions `module.dialogflow` (`ai-applications` Fabric module) in [`1-apps/main.tf`](./1-apps/main.tf) with:
  - `faq` data store (`NO_CONTENT`, `SOLUTION_TYPE_CHAT`) in `var.region_discovery_engine` (`eu` or `us`)
  - `kb` data store (`CONTENT_REQUIRED`, `SOLUTION_TYPE_CHAT`, layout parsing + 500-token chunking, custom schema `./data/ds-kb/ds-kb-schema.json`) in `var.region_discovery_engine`
  - Dialogflow CX chat engine (`allow_cross_region = true`) in `var.region` (`europe-west1`)
- Provisions a private 2nd Gen Cloud Run Function (`1-apps/cloud-functions.tf`) from `data/function`, fronted by an Internal Regional TCP Proxy LB with a CAS-issued private certificate (`privateca.googleapis.com`), and registered in Service Directory (`1-apps/on-prem-services.tf`).

#### Recipe B: Custom Agent Variant, Language, or On-Premises Service Directory Endpoints

```hcl
region                  = "europe-west1"
region_discovery_engine = "eu" # "eu" or "us"

agent_configs = {
  language = "en"
  variant  = "default" # Folder name under 1-apps/data/agents/<variant>
}

service_directory_configs = {
  default = {
    cloud_dns_domain = "example.com"
    endpoints = {
      onprem-01 = {
        address   = "192.168.0.100"
        port      = 443
        create_lb = true
      }
    }
    services = {
      onprem = {
        endpoints = ["onprem-01"]
      }
    }
  }
}
```

### Step 3: Apply Stage 1 (`1-apps`)

```shell
cd 1-apps
terraform init
terraform apply
```

### Step 4: Import FAQ & KB Documents, Restore the Agent, and Test `detectIntent`

View and execute the post-apply commands generated from [`1-apps/templates/outputs.sh`](./1-apps/templates/outputs.sh):

```shell
terraform output -raw commands
```

The generated script performs 5 steps (impersonating `service-01/iac-rw`):

1. **Imports structured FAQ data (`faq.csv`):** Uploads `./data/ds-faq/faq.csv` to the `ds` GCS bucket and calls `documents:import` (`dataSchema = "csv"`, `autoGenerateIds = true`, `reconciliationMode = "FULL"`) on the `faq` data store.
2. **Processes & imports unstructured KB documents (`ds-kb`):** Runs `uv run ./scripts/agentutil/agentutil.py process-documents ./data/ds-kb/ ./build/data/ds-kb/ <bucket_url_ds>/ds-kb/ --upload` to generate `documents.jsonl` and calls `documents:import` (`dataSchema = "document"`) on the `kb` data store.
3. **Builds & restores the Dialogflow CX agent archive (`agent.dist.zip`):** Copies `./data/agents/<variant>/*` to `./build/agent/dist`, runs `agentutil.py replace-data-store` for both `UNSTRUCTURED` (`kb`) and `STRUCTURED` (`faq`), zips the bundle, uploads it to GCS, and calls the Dialogflow CX `agents:restore` API.
4. **Registers private Service Directory webhooks:** Runs `uv run ./scripts/agentutil/agentutil.py create-webhook` for each Service Directory webhook in `local.webhooks`.
5. **Verifies the agent via `detectIntent`:** Calls `POST https://<region>-dialogflow.googleapis.com/v3/<agent_id>/environments/draft/sessions/any-session-id:detectIntent` with `"Hello, bot"`.

______________________________________________________________________

## 4. Factory-Specific Troubleshooting (`gecx-dialogflow`)

### 1. Document Indexing Delay Before Querying Knowledge Base

- **Cause:** After calling `documents:import` on the `faq` and `kb` Discovery Engine data stores, initial indexing and layout chunking take **5–15 minutes**.
- **Fix:** Check the import operation status in the Google Cloud Console (AI Applications -> Data Stores) before testing knowledge-base-backed intents via `detectIntent`.

### 2. Regional Prefix Differences Between Dialogflow (`var.region`) and Discovery Engine (`var.region_discovery_engine`)

- As implemented in [`1-apps/outputs.tf`](./1-apps/outputs.tf), Dialogflow CX REST calls use `https://<region>-dialogflow.googleapis.com/v3/...` (e.g., `europe-west1-dialogflow.googleapis.com`), whereas Discovery Engine import calls use `https://<region_discovery_engine>-discoveryengine.googleapis.com/v1/...` (e.g., `eu-discoveryengine.googleapis.com`). Never mix the two prefixes when crafting manual `curl` requests.
