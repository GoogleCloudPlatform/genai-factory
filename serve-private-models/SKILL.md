---
name: serve-private-models
description: Actionable runbook for configuring, deploying, customizing, and operating the serve-private-models factory (Vertex AI Model Garden open models such as Gemma 3 privately exposed via Private Service Connect to a Cloud Run application with Load Balancer, Cloud Armor, and Model Armor). Use this skill whenever a user asks to deploy or configure serve-private-models, deploy a custom publisher or Hugging Face model on a private Vertex AI Endpoint, connect Cloud Run over PSC to a private Vertex AI Endpoint, or troubleshoot Model Garden EULA/GPU quotas and private endpoint prediction calls.
---

# Serve Private Models — Deployment & Operations Runbook

This skill guides you through configuring, deploying, customizing, and troubleshooting the [`serve-private-models`](./README.md) factory: an open model from **Vertex AI Model Garden** (defaulting to `gemma3@gemma-3-1b-it` on `g2-standard-12` with `1x NVIDIA_L4`) deployed on a private **Vertex AI Endpoint** exposed via **Private Service Connect (PSC)**, fronted by a **Cloud Run** application behind an optional **External/Internal Application Load Balancer**, **Cloud Armor**, and **Model Armor**.

> [!NOTE]
> For repository contributor workflows (regenerating `plan_summary.py` test inventories and running `pytest`), also consult [`serve-private-models/AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Shared Skills Reference (Do Not Duplicate)

This factory relies on the repository's shared skills in [`../.agents/skills/`](../.agents/skills/README.md) for cross-cutting workflows. Always load the relevant shared skill first:

| Workflow Area | Shared Skill | How `serve-private-models` Uses It |
| :--- | :--- | :--- |
| **Stage 0 (`0-prereqs`), BYO-VPC, Fabric FAST, & `*.rep.googleapis.com` PSC/DNS** | [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) | Deploys Host (`gf-mg-hp-0`) & Service (`gf-mg-0`) projects, Shared VPC, regional PSC endpoints (`aiplatform.<eu\|us>.rep.googleapis.com`, `modelarmor.<region>.rep.googleapis.com`), or wires BYO-VPC / FAST inputs. |
| **Cloud Run Frontend, External/Internal ALB, Cloud Armor, CAS, Direct Ingress** | [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md) | Configures `lbs_configs`, `ca_pool_name_suffix`, `cloud_run_config`, and Cloud Build container deployments. |
| **Model Armor Templates & Floor Settings** | [`model-armor`](../.agents/skills/model-armor/SKILL.md) | Configures `model_armor_template_config` and `model_armor_floorsetting_config`. |
| **Impersonation Quota Fixes, Networking Debugging & Clean Teardown** | [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md) | Resolves `403 serviceusage.services.use`, Serverless VPC IP reservation teardown delays, and cleans up generated `1-apps` files. |

______________________________________________________________________

## 2. Factory-Specific Resource & Identity Identifiers

When applying the patterns in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md), use these exact `serve-private-models` identifiers:

- **Default Resource Name (`var.name` in `1-apps`):** `"gf-mg-0"`
- **Stage 0 Project YAML Templates:**
  - Service project (`gf-mg-0`): [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - Host project (`gf-mg-hp-0`): [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
- **Required `service_account_emails` / `service_account_ids` Map Keys in `1-apps`:**
  - `"service-01/iac-rw"` — Stage 1 Terraform deployer SA (`<prefix>-gf-mg-0-rw@...`). Also holds a custom organizational role (`model_garden_deployer` with `aiplatform.consents.update` and Service Directory permissions) and additive `roles/aiplatform.user`.
  - `"service-01/crun-0"` — Cloud Run runtime SA (`<prefix>-gf-mg-0-cr@...`, holds `roles/aiplatform.user` and `roles/modelarmor.user`).
  - `"service-01/crun-build-0"` — Cloud Build SA (`<prefix>-gf-mg-0-cb@...`).
- **Required Host Project Shared VPC Grants:**
  - `roles/compute.networkUser` on the Shared VPC subnet for `service-01/iac-rw` and the Cloud Run service agent (`service-01/run`).
  - Note: Unlike Cloud SQL or AlloyDB PSC, `serve-private-models` creates an internal consumer IP (`module.psc_consumer_address`) and a consumer PSC forwarding rule (`google_compute_forwarding_rule.psc_consumer_fwd_rule` with `allow_psc_global_access = true`) directly in the service project (`var.project_id`) targeting the Vertex AI Endpoint's `service_attachment` ([`1-apps/model-garden.tf`](./1-apps/model-garden.tf)).
- **Required `provider "google"` Region in `1-apps/providers.tf`:**
  - `google_vertex_ai_endpoint_with_model_garden_deployment` does **not** inherit the region from `location` alone when building the regional Vertex AI API URL (`https://<region>-aiplatform.googleapis.com/...`). Always ensure `region = "<region>"` is set in both `provider "google"` and `provider "google-beta"` blocks in `1-apps/providers.tf` (handled automatically by [`0-prereqs/templates/providers.tf.tpl`](./0-prereqs/templates/providers.tf.tpl)).

______________________________________________________________________

## 3. Step-by-Step Deployment Workflow

### Step 1: Run Stage 0 (`0-prereqs`)

Follow [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) in [`0-prereqs/`](./0-prereqs/README.md).

### Step 2: Configure Stage 1 (`1-apps/terraform.tfvars`)

In [`1-apps/`](./1-apps/README.md), combine any Load Balancer or Model Armor recipes from [`cloud-run-and-load-balancers`](../.agents/skills/cloud-run-and-load-balancers/SKILL.md) and [`model-armor`](../.agents/skills/model-armor/SKILL.md) with the Model Garden recipes below.

#### Recipe A: Default Gemma 3 (`gemma3@gemma-3-1b-it` on Spot L4 GPU)

No `model_garden_config` overrides are required; defaults in [`1-apps/variables.tf`](./1-apps/variables.tf) deploy `publishers/google/models/gemma3@gemma-3-1b-it` on `1x NVIDIA_L4` (`g2-standard-12`) with `spot = true` and `accept_eula = true`.

#### Recipe B: Custom Publisher Model or On-Demand (Non-Spot) GPU Replica Scaling

```hcl
model_garden_config = {
  accept_eula          = true
  publisher_model_name = "publishers/google/models/gemma3@gemma-3-4b-it"
  spot                 = false
  min_replica_count    = 1
  max_replica_count    = 2
  machine_spec = {
    machine_type      = "g2-standard-12"
    accelerator_type  = "NVIDIA_L4"
    accelerator_count = 1
  }
}
```

#### Recipe C: Hugging Face Model ID Instead of Publisher Model

`publisher_model_name` and `hugging_face_model_id` are mutually exclusive in `google_vertex_ai_endpoint_with_model_garden_deployment`:

```hcl
model_garden_config = {
  accept_eula           = true
  publisher_model_name  = null
  hugging_face_model_id = "google/gemma-3-1b-it"
  spot                  = true
  machine_spec = {
    machine_type      = "g2-standard-12"
    accelerator_type  = "NVIDIA_L4"
    accelerator_count = 1
  }
}
```

> [!IMPORTANT]
> **Cloud Run VPC Egress Must Stay `ALL_TRAFFIC` (or Reach Private Ranges):**
> `cloud_run_config.vpc_access_egress` defaults to `"ALL_TRAFFIC"` in [`1-apps/variables.tf`](./1-apps/variables.tf) so the Cloud Run container routes traffic to the internal PSC consumer forwarding rule IP (`ENDPOINT_IP_ADDRESS`) over Direct VPC Egress.

### Step 3: Apply Stage 1 (`1-apps`)

```shell
cd 1-apps
terraform init
terraform apply
```

> [!NOTE]
> Deploying a Vertex AI Model Garden endpoint (`google_vertex_ai_endpoint_with_model_garden_deployment.model_garden`) typically takes **15–25 minutes** while Vertex AI provisions the GPU node and loads model weights.

### Step 4: Build & Deploy the Sample Chat Application (`apps/chat`)

View the generated deployment command:

```shell
terraform output -raw commands
```

As defined in [`1-apps/outputs.tf`](./1-apps/outputs.tf), `commands` runs `gcloud run deploy` from [`1-apps/apps/chat/`](./1-apps/apps/chat/README.md) with:

- `PROJECT_ID` — Service project ID
- `REGION` — GCP region (e.g., `europe-west1`)
- `ENDPOINT_ID` — Numeric Vertex AI Endpoint ID (`google_vertex_ai_endpoint_with_model_garden_deployment.model_garden.endpoint_id`)
- `ENDPOINT_IP_ADDRESS` — Internal PSC consumer IP (`module.psc_consumer_address.address`)
- `MODEL_ARMOR_TEMPLATE` — Full resource ID of the Model Armor template

> [!TIP]
> Remember to set `export CLOUDSDK_BILLING_QUOTA_PROJECT="<service-project-id>"` before running impersonated `gcloud` commands (see [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md)).

______________________________________________________________________

## 4. Verifying & Customizing the Application (`1-apps/apps/chat`)

### Testing the Deployed Application

Follow [`1-apps/apps/chat/README.md`](./1-apps/apps/chat/README.md) to query the `/chat` endpoint:

```shell
curl -X POST "https://<YOUR_DOMAIN_OR_RUN_URL>/chat" \
  -H "Content-Type: application/json" \
  -d '{"message": "Explain quantum computing in simple terms."}'
```

### How Private PSC Endpoint Prediction Works in Python

Inspect [`1-apps/apps/chat/main.py`](./1-apps/apps/chat/main.py) and [`1-apps/apps/chat/src/config.py`](./1-apps/apps/chat/src/config.py):

1. The application installs `google-cloud-aiplatform[private_endpoints]` in [`1-apps/apps/chat/pyproject.toml`](./1-apps/apps/chat/pyproject.toml).
2. It initializes `aiplatform.init(project=config.PROJECT_ID, location=config.REGION)` and constructs an `aiplatform.PrivateEndpoint(endpoint_name=config.ENDPOINT_ID)`.
3. It calls `endpoint.predict(instances=[...], endpoint_override=config.ENDPOINT_IP_ADDRESS)` so prediction requests go directly over HTTP/gRPC to the internal PSC consumer forwarding rule IP (`ENDPOINT_IP_ADDRESS`) in the VPC rather than the public Vertex AI prediction API.
4. When modifying dependencies in [`1-apps/apps/chat/pyproject.toml`](./1-apps/apps/chat/pyproject.toml), always run `uv lock` inside `1-apps/apps/chat/` because the [`Dockerfile`](./1-apps/apps/chat/Dockerfile) runs `uv sync --locked`.

______________________________________________________________________

## 5. Factory-Specific Troubleshooting (`serve-private-models`)

For general `gcloud` impersonation quota issues, `*.rep.googleapis.com` private networking, and Serverless VPC IP reservation delays during destroy, see [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md).

### 1. `400 URL notable to be parsed: https://-aiplatform.googleapis.com/...`

- **Cause:** `google_vertex_ai_endpoint_with_model_garden_deployment` constructs the regional API URL from the provider-level `region` attribute; if `region` is omitted from `provider "google"` / `provider "google-beta"` in `1-apps/providers.tf`, the hostname starts with `-aiplatform`.
- **Fix:** Add `region = "<your-region>"` to both provider blocks in `1-apps/providers.tf`.

### 2. `403 Permission 'aiplatform.consents.update' denied` or EULA Acceptance Error

- **Cause:** Deploying gated publisher models (such as Gemma 3) with `accept_eula = true` requires `aiplatform.consents.update` on the Stage 1 deployer SA (`service-01/iac-rw`).
- **Fix:** Verify `0-prereqs` was applied with the custom project role `model_garden_deployer` defined and bound in [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml), or accept the model EULA manually in the Google Cloud Console Model Garden UI.

### 3. GPU Quota Exhausted (`QUOTA_EXCEEDED` / `ZONE_RESOURCE_POOL_EXHAUSTED`)

- **Cause:** Insufficient regional quota for `NVIDIA_L4_GPUS` (or Preemptible/Spot `NVIDIA_L4_GPUS` when `spot = true`), or temporary regional stockout.
- **Fix:** Check IAM & Admin -> Quotas for `NVIDIA_L4_GPUS` (and Spot L4 GPUs) in `var.region`, switch `model_garden_config.spot = false` if Spot capacity is unavailable, or deploy in another supported region.
