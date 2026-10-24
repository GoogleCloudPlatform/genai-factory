---
name: cloud-run-and-load-balancers
description: >-
  Shared runbook for configuring Cloud Run services and jobs, External and
  Internal Application Load Balancers (lbs_configs), Cloud Armor IP allowlists,
  Certificate Authority Service (CAS) private certificates (ca_pool_name_suffix),
  Direct Cloud Run ingress testing, Cloud Build container submissions, and
  Python GenAI/ADK application conventions across genai-factory blueprints.
---

# Cloud Run, Load Balancers & Application Lifecycle (`cloud-run-and-load-balancers`)

This shared skill covers the Cloud Run exposure layer (`lb-ext.tf`, `lb-int.tf`, `lb-int-cert.tf`), `terraform.tfvars` recipes, and Python container build/deploy workflows shared by `cloud-run-single`, `cloud-run-nl2sql-bq`, `cloud-run-rag-alloydb`, `cloud-run-rag-cloudsql`, `cloud-run-rag-search`, and `serve-private-models`.

______________________________________________________________________

## 1. Exposure Layer Configuration Recipes (`1-apps/terraform.tfvars`)

All Cloud Run factories expose `lbs_configs`, `ca_pool_name_suffix`, and `cloud_run_config` (or `cloud_run_configs.frontend` in multi-service RAG factories) in `1-apps/variables.tf`.

### Recipe A — External HTTPS Load Balancer + Cloud Armor (Default)

Provisions a Global External Application Load Balancer (`1-apps/lb-ext.tf`) with HTTP-to-HTTPS redirect, a Google-managed SSL certificate, and a Cloud Armor IP allowlist security policy.

```hcl
lbs_configs = {
  external = {
    enable            = true
    domain            = "ai.example.com"
    allowed_ip_ranges = ["203.0.113.0/24"] # Defaults to ["0.0.0.0/0"]
    # ip_address      = "34.x.x.x"         # Optional pre-reserved global IP
  }
}
```

- **Post-apply action**: Create a public DNS `A` record for `domain` pointing to `terraform output -json ip_addresses | jq -r .external` so the Google-managed certificate can complete provisioning.

### Recipe B — Internal Application Load Balancer (ILB) + CAS Private Certificates

Provisions a Regional Internal Application Load Balancer (`1-apps/lb-int.tf`), a Certificate Authority Service (CAS) private CA pool (`1-apps/lb-int-cert.tf`), a Certificate Manager certificate, a regional Cloud Armor policy, and a private Cloud DNS zone for `domain`.

```hcl
lbs_configs = {
  external = {
    enable = false
  }
  internal = {
    enable            = true
    domain            = "ai.internal.example.com"
    allowed_ip_ranges = ["10.0.0.0/8"]
  }
}

# CA pools cannot be recreated with the same name in the same project while
# deletion is pending. Increment this suffix when re-deploying in the same project:
ca_pool_name_suffix = "ca-pool-1"
```

- **Prerequisite**: Requires a `REGIONAL_MANAGED_PROXY` (proxy-only) subnet in `var.region` (created automatically by `0-prereqs` when `networking_config.create = true`).

### Recipe C — Direct Cloud Run Access (No Load Balancer / Rapid Testing)

Disables both load balancers and exposes the Cloud Run `.run.app` URL directly while keeping IAM authentication enforced (`roles/run.invoker`).

- For **single-service factories** (`cloud-run-single`, `cloud-run-nl2sql-bq`, `serve-private-models`):

  ```hcl
  lbs_configs = {
    external = { enable = false }
    internal = { enable = false }
  }

  cloud_run_config = {
    ingress          = "INGRESS_TRAFFIC_ALL"
    service_invokers = ["user:developer@example.com"]
  }
  ```

- For **RAG factories with frontend + ingestion** (`cloud-run-rag-alloydb`, `cloud-run-rag-cloudsql`, `cloud-run-rag-search`):

  ```hcl
  lbs_configs = {
    external = { enable = false }
    internal = { enable = false }
  }

  cloud_run_configs = {
    frontend = {
      ingress          = "INGRESS_TRAFFIC_ALL"
      service_invokers = ["user:developer@example.com"]
    }
    ingestion = {}
  }
  ```

### Recipe D — Scheduled Ingestion Job & Scaling (`cloud-run-rag-*` Factories)

All three Cloud Run RAG factories (`cloud-run-rag-alloydb`, `cloud-run-rag-cloudsql`, `cloud-run-rag-search`) provision a Cloud Scheduler job (`ingestion_schedule_configs`) that triggers the `${var.name}-ingestion` Cloud Run Job every 30 minutes by default:

```hcl
ingestion_schedule_configs = {
  schedule         = "0 */6 * * *" # Default: "*/30 * * * *"
  attempt_deadline = "180s"        # Default: "60s"
  retry_count      = 3
}

cloud_run_configs = {
  frontend = {
    min_instance_count = 1
    max_instance_count = 5
    service_invokers   = ["user:developer@example.com"]
  }
  ingestion = {}
}
```

______________________________________________________________________

## 2. Building, Deploying & Customizing Python Applications

In all Cloud Run factories, the `cloud-run-v2` Terraform module sets `managed_revision = false`. Terraform manages the infrastructure envelope (IAM, Direct VPC egress, scaling, LBs), while container builds and Cloud Run revisions are deployed via the commands printed by:

```shell
terraform output -raw commands
```

### Standard Build & Deploy Flow

1. **Create Artifact Registry repository** (once per environment) using `gcloud artifacts repositories create` impersonating `service-01/iac-rw`.
2. **Submit container build** via `gcloud builds submit` using the dedicated build service account (`--service-account ...crun-build-0`), `--default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET`, and `--impersonate-service-account=...iac-rw`.
3. **Deploy Cloud Run revision** (or update Cloud Run Job) via `gcloud run deploy` / `gcloud run jobs update` with the `--set-env-vars` values emitted by Terraform outputs.

### Mandatory Conventions When Modifying or Creating Sample Apps

1. **Separate `REGION` and `GOOGLE_CLOUD_LOCATION`**:
   - `google-genai` (`genai.Client`) and `google-adk` automatically read `GOOGLE_CLOUD_LOCATION` from the environment.
   - Keep `REGION` (e.g., `europe-west1` for regional services like Model Armor or Vector Search) distinct from `GOOGLE_CLOUD_LOCATION` (`eu` or `us` for multi-regional Vertex AI Gemini models such as `gemini-4-argon`).
2. **Expose `THINKING_LEVEL` (or `LLM_THINKING_LEVEL` in RAG apps)**:
   - Define `THINKING_LEVEL = os.environ.get("THINKING_LEVEL", "MEDIUM")` in `src/config.py` and pass `thinking_config=types.ThinkingConfig(thinking_level=...)` inside `types.GenerateContentConfig(...)`.
3. **Batch Embeddings (`<= 250` inputs per call)**:
   - When using `gemini-embedding-001` (`3072` dimensions), `client.models.embed_content` (and Vector Search 2.0 auto-embedding batch APIs) enforce a hard limit of at most **250** inputs per request. Always chunk document lists into batches of `<= 250`.
4. **Update `uv.lock` whenever `pyproject.toml` changes**:
   - Every sample application `Dockerfile` runs `uv sync --frozen` (or `uv sync --locked`). Whenever `pyproject.toml` is modified, run `uv lock` inside that application folder before running `gcloud builds submit`, otherwise Cloud Build will fail.
5. **Authenticate test requests with an Identity Token**:
   - Pass `-H "Authorization: Bearer $(gcloud auth print-identity-token)"` in `curl` requests and ensure the caller has `roles/run.invoker` via `service_invokers`.
