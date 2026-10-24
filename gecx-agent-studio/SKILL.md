---
name: gecx-agent-studio
description: Actionable runbook for configuring, deploying, customizing, and operating the gecx-agent-studio factory (Gemini Enterprise for Customer Experience / CX Agent Studio with Discovery Engine data stores, private Cloud Run and on-prem OpenAPI toolsets exposed via Service Directory and Internal Regional TCP Proxy Load Balancers, and agentutil.py lifecycle automation). Use this skill whenever a user asks to deploy or configure gecx-agent-studio, wire private OpenAPI toolsets over Service Directory, ingest knowledge base documents and push CES agents with agentutil.py, or troubleshoot CES Service Directory TLS/CA certificate validation.
---

# GECX Agent Studio — Deployment & Operations Runbook

This skill guides you through configuring, deploying, customizing, and troubleshooting the [`gecx-agent-studio`](./README.md) factory: a **Gemini Enterprise for Customer Experience (CX Agent Studio / `google_ces_app`)** deployment with **Discovery Engine** knowledge base data stores (`google_discovery_engine_data_store`) and private **Cloud Run** and **on-premises** OpenAPI toolsets reached privately over **Service Directory** and **Internal Regional TCP Proxy Load Balancers**.

> [!NOTE]
> For repository contributor workflows (regenerating `plan_summary.py` test inventories and running `pytest`), also consult [`gecx-agent-studio/AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Shared Skills Reference (Do Not Duplicate)

This factory relies on the repository's shared skills in [`../.agents/skills/`](../.agents/skills/README.md) for cross-cutting workflows. Always load the relevant shared skill first:

| Workflow Area | Shared Skill | How `gecx-agent-studio` Uses It |
| :--- | :--- | :--- |
| **Stage 0 (`0-prereqs`), BYO-VPC, Fabric FAST** | [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) | Deploys Host (`gf-gecx-as-hp-0`) & Service (`gf-gecx-as-0`) projects, Shared VPC, and Service Directory / Cloud DNS host project bindings. |
| **Discovery Engine Data Stores & Private Service Directory + Internal TCP Proxy LB Architecture** | [`discovery-engine-and-gecx`](../.agents/skills/discovery-engine-and-gecx/SKILL.md) | Explains `region_discovery_engine` (`eu`/`us`), `service_directory_configs`, Internal Regional TCP Proxy LB + DER certificate requirements, and `agentutil.py` workflows. |
| **Impersonation Quota Fixes, Networking Debugging & Clean Teardown** | [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md) | Resolves `403 serviceusage.services.use`, Serverless VPC IP reservation teardown delays, and cleans up generated `1-apps` files. |

______________________________________________________________________

## 2. Factory-Specific Resource & Identity Identifiers

When applying the patterns in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) and [`discovery-engine-and-gecx`](../.agents/skills/discovery-engine-and-gecx/SKILL.md), use these exact `gecx-agent-studio` identifiers:

- **Default Resource Name (`var.name` in `1-apps`):** `"cx-as-0"`
- **Stage 0 Project YAML Templates:**
  - Service project (`gf-gecx-as-0`): [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml) (enables `ces.googleapis.com`, `discoveryengine.googleapis.com`, `servicedirectory.googleapis.com`, `run.googleapis.com`, `dns.googleapis.com`).
  - Host project (`gf-gecx-as-hp-0`): [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml).
- **Required `service_account_emails` Map Keys in `1-apps`:**
  - `"service-01/iac-rw"` — Stage 1 Terraform & `agentutil.py` deployer SA (`<prefix>-gf-gecx-as-0-rw@...`, holds `roles/ces.admin`, `roles/discoveryengine.admin`, `roles/servicedirectory.admin`, `roles/dns.admin`, `roles/run.admin`, `roles/compute.loadBalancerAdmin`, `roles/certificatemanager.owner`, `roles/storage.admin`).
  - `"service-01/gecx-as-0"` — Cloud Run toolset runtime SA (`<prefix>-gf-gecx-as-0-cr@...`).
- **Required Service Agent IAM Bindings:**
  - **Service project (`service-01.yaml`):**
    - CES service agent (`service-01/ces`): `roles/servicedirectory.viewer`
    - Certificate Manager service agent (`service-01/certificatemanager`): `roles/privateca.certificateRequester`
  - **Host project (`host.yaml`):**
    - CES service agent (`service-01/ces`): `roles/servicedirectory.pscAuthorizedService`
    - Deployer SA (`service-01/iac-rw`): `roles/compute.networkUser`, `roles/dns.admin`, `roles/servicedirectory.networkAttacher`
    - Cloud Run service agent (`service-01/run`): `roles/compute.networkUser`
- **Additional `networking_config` Attribute in `1-apps`:**
  - Unlike Cloud Run factories, `gecx-agent-studio/1-apps` requires `networking_config.host_project_number` alongside `subnet` and `vpc` ([`1-apps/variables.tf`](./1-apps/variables.tf)).

______________________________________________________________________

## 3. Step-by-Step Deployment Workflow

### Step 1: Run Stage 0 (`0-prereqs`)

Follow [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) in [`0-prereqs/`](./0-prereqs/README.md).

### Step 2: Configure Stage 1 (`1-apps/terraform.tfvars`)

In [`1-apps/`](./1-apps/README.md), consult [`discovery-engine-and-gecx`](../.agents/skills/discovery-engine-and-gecx/SKILL.md) for the Service Directory + Internal Regional TCP Proxy LB architecture, and customize `1-apps/terraform.tfvars` using the recipes below.

#### Recipe A: Default Deployment (CES App `cx-as-0`, Datastore `cx-as-0-ds`, Private Cloud Run & On-Prem Toolsets)

No `terraform.tfvars` overrides are required beyond `terraform.auto.tfvars` generated by Stage 0:

- Provisions `google_ces_app.gecx_as_app["cx-as-0"]` and `google_discovery_engine_data_store.datastore["cx-as-0"]` in `var.region_discovery_engine` (`eu` or `us`).
- Provisions a private Cloud Run service (`cx-as-0`) fronted by an Internal Regional TCP Proxy LB (`1-apps/cloud-run-lb.tf`) and registered in Service Directory (`example-com` namespace, `run` service).
- Provisions an Internal Regional TCP Proxy LB and Service Directory service (`onprem`) for the sample on-prem endpoint (`10.0.0.2:443`) in [`1-apps/private-network-access.tf`](./1-apps/private-network-access.tf).

#### Recipe B: Customizing `agents_configs`, `datastores_configs`, and `service_directory_configs`

```hcl
region_discovery_engine = "eu" # Must be "eu" or "us"

datastores_configs = {
  cx-as-0 = {
    schema_path = "data/datastores/ds-kb/knowledge_base_data_store_schema.json"
  }
}

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
      "onprem/onprem-01" = {
        address   = "10.0.0.2"
        port      = 443
        create_lb = true
      }
    }
    services = {
      onprem = {
        endpoints    = ["onprem-01"]
        openapi_spec = "data/onprem/openapi-spec.yaml"
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

### Step 4: Ingest Data Stores, Wire Toolsets, and Push the CES Agent (`agentutil.py`)

View and execute the post-apply commands generated from [`1-apps/templates/outputs.sh`](./1-apps/templates/outputs.sh):

```shell
terraform output -raw commands
```

The generated script uses [`1-apps/scripts/agentutil.py`](./1-apps/scripts/agentutil.py) (impersonating `service-01/iac-rw`) to:

1. **Ingest knowledge base documents** (`uv run scripts/agentutil.py data-store ingest ...`) from `data/datastores/ds-kb/` into GCS and the Discovery Engine data store (`cx-as-0-ds`).
2. **Stage the CES agent bundle** from `./data/apps/cx-as-0` into `./build/app/dist/cx-as-0/agent`.
3. **Replace datastore placeholders** (`uv run scripts/agentutil.py ces agent replace-data-store ...`) so `kb_data_store` references the newly created Discovery Engine data store resource name.
4. **Register private OpenAPI toolsets** (`uv run scripts/agentutil.py create-toolset ...`) for both the private Cloud Run service (`run-example-com`, including its base64-encoded DER CA cert from `data/cloud-run/cert.der` and OpenAPI spec `data/cloud-run/openapi-spec.yaml`) and any `service_directory_configs` services.
5. **Push the agent bundle** (`uv run scripts/agentutil.py ces agent push ...`) to `projects/<project_id>/locations/<region_discovery_engine>/apps/cx-as-0`.

______________________________________________________________________

## 4. Customizing & Operating `gecx-agent-studio`

### 1. Why `google_ces_app` Ignores Content Changes After First Apply

- In [`1-apps/main.tf`](./1-apps/main.tf), `google_ces_app.gecx_as_app` sets `lifecycle { ignore_changes = [description, data_store_settings, global_instruction, guardrails, language_settings, pinned, root_agent, variable_declarations, audio_processing_config, time_zone_settings] }`.
- This is intentional: Terraform bootstraps the empty CES app shell, and [`scripts/agentutil.py`](./1-apps/scripts/agentutil.py) (or the CX Agent Studio UI at `https://ces.cloud.google.com/projects/<project_id>/locations/<region_discovery_engine>/apps/<app_id>`) owns subsequent prompt, guardrail, datastore, and toolset updates.

### 2. Custom TLS Certificates for Private Cloud Run Toolsets

- If you change `cloud_run_config.cert_common_name` (default `"example.com"`) or replace the certificates in `1-apps/data/cloud-run/`, ensure:
  - `cert.der` is in binary **DER** format (required by CES `allowed_ca_certs`, which base64-encodes the DER bytes in [`1-apps/outputs.tf`](./1-apps/outputs.tf)).
  - The Subject Alternative Name (SAN) / Common Name on the certificate matches `<service_id>.<cert_common_name>` (the URI constructed in `local.toolsets["run-example-com"].uri`).
  - The `servers:` URL inside `data/cloud-run/openapi-spec.yaml` matches the toolset's HTTPS hostname.
