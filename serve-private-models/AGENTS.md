# Serve Private Models (`serve-private-models`) — Agent Instructions

For repository-wide conventions, Terraform style rules, and cross-cutting learnings, see the root [`AGENTS.md`](../AGENTS.md).

## Overview & Architecture

The `serve-private-models` factory (project abbreviation `mg`) is the reference blueprint for privately deploying open models from **Vertex AI Model Garden** (such as Gemma 3) on a **Private Service Connect (PSC)** endpoint and exposing them through a **Cloud Run** application behind an external or internal Application Load Balancer with Cloud Armor and Model Armor:

- **`0-prereqs`** ([`0-prereqs/README.md`](./0-prereqs/README.md)):
  - Service project ([`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml), `gf-mg-0`) and optional Shared VPC host project ([`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml), `gf-mg-hp-0`).
  - VPC, subnet, Private Google Access, Cloud DNS response policies, and regional PSC endpoints ([`0-prereqs/networking.tf`](./0-prereqs/networking.tf)) for multi-regional Vertex AI (`aiplatform.<multi_region>.rep.googleapis.com`) and regional Model Armor (`modelarmor.<region>.rep.googleapis.com`).
  - Least-privilege Stage 1 automation service account (`iac-rw`) granted `roles/aiplatform.user` (additive) and a minimal custom role (`model_garden_deployer` with `aiplatform.consents.update`), plus `roles/compute.networkUser` on the host project to reserve the PSC consumer IP and attach the PSC forwarding rule on the Shared VPC.
- **`1-apps`** ([`1-apps/README.md`](./1-apps/README.md)):
  - **Model Garden Private Endpoint & PSC Consumer** ([`1-apps/model-garden.tf`](./1-apps/model-garden.tf)): Deploys `google_vertex_ai_endpoint_with_model_garden_deployment` with `enable_private_service_connect = true` (defaulting to `publishers/google/models/gemma3@gemma-3-1b-it` on `g2-standard-12` with `1x NVIDIA_L4`), reserves an internal IP via `net-address`, and creates a `google_compute_forwarding_rule` targeting the endpoint's `service_attachment`.
  - **Cloud Run Service** ([`1-apps/main.tf`](./1-apps/main.tf)): Runs the application container with Direct VPC egress (`ALL_TRAFFIC`) to reach the PSC forwarding rule IP in the Shared VPC.
  - **Model Armor** ([`1-apps/model-armor.tf`](./1-apps/model-armor.tf)): Regional Model Armor template (`google_model_armor_template`) and floor settings (`google_model_armor_floorsetting`) for prompt and response sanitization.
  - **Application Load Balancer & Cloud Armor** ([`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), [`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/lb-int-cert.tf`](./1-apps/lb-int-cert.tf)): External or internal HTTPS load balancer with Cloud Armor WAF policy.
  - **Sample Application** ([`1-apps/apps/chat/`](./1-apps/apps/chat)): FastAPI application using `google.cloud.aiplatform.PrivateEndpoint` with `endpoint_override=ENDPOINT_IP_ADDRESS` to send chat completion requests privately over PSC, with optional Model Armor inspection.

## Key Files & Test Cases

- **Stage 0 (`0-prereqs`)**:
  - [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
  - [`0-prereqs/networking.tf`](./0-prereqs/networking.tf)
- **Stage 1 (`1-apps`)**:
  - [`1-apps/model-garden.tf`](./1-apps/model-garden.tf), [`1-apps/main.tf`](./1-apps/main.tf), [`1-apps/model-armor.tf`](./1-apps/model-armor.tf), [`1-apps/lb-ext.tf`](./1-apps/lb-ext.tf), [`1-apps/lb-int.tf`](./1-apps/lb-int.tf), [`1-apps/variables.tf`](./1-apps/variables.tf), [`1-apps/outputs.tf`](./1-apps/outputs.tf)
  - Sample application: [`1-apps/apps/chat/`](./1-apps/apps/chat)
- **Tests** ([`tests/serve_private_models/`](../tests/serve_private_models)):
  - `0_prereqs`: `simple`, `no_host_prj`
  - `1_apps`: `simple`

## Testing & Inventory Regeneration

```shell
# Run all serve-private-models tests
uv run pytest tests/serve_private_models

# Regenerate 0-prereqs inventories
for t in simple no_host_prj; do
  uv run tools/plan_summary.py serve-private-models/0-prereqs \
    tests/serve_private_models/0_prereqs/${t}.tfvars \
    > tests/serve_private_models/0_prereqs/${t}.yaml
done

# Regenerate 1-apps inventory
uv run tools/plan_summary.py serve-private-models/1-apps \
  tests/serve_private_models/1_apps/simple.tfvars \
  > tests/serve_private_models/1_apps/simple.yaml

# Format regenerated YAML files
uv run yamlfix tests/serve_private_models
```

## Factory-Specific Learnings & Gotchas

- **Provider-Level `region` Required for `google_vertex_ai_endpoint_with_model_garden_deployment`:**
  - The Terraform resource `google_vertex_ai_endpoint_with_model_garden_deployment` defines `location` (rather than `region`) in its schema, while the Vertex AI MMv1 product base URL template uses `https://{{region}}-aiplatform.googleapis.com/v1/`. Consequently, `region` must be configured on the `google` and `google-beta` provider blocks in [`0-prereqs/templates/providers.tf.tpl`](./0-prereqs/templates/providers.tf.tpl).
- **Least-Privilege IAM for Model Garden & PSC Deployment (`model_garden_deployer`):**
  - `roles/aiplatform.user` contains all endpoint and model deployment permissions except `aiplatform.consents.update` (which is required when `accept_eula = true` on `google_vertex_ai_endpoint_with_model_garden_deployment`).
  - `roles/compute.loadBalancerAdmin` includes `compute.addresses.createInternal` and `compute.forwardingRules.pscCreate`, while Compute Engine's automatic registration of PSC forwarding rules in the default `goog-psc-default` Service Directory namespace requires `servicedirectory.namespaces.create`, `servicedirectory.namespaces.delete`, `servicedirectory.services.create`, and `servicedirectory.services.delete`.
  - Granting `roles/aiplatform.user` (additive), `roles/compute.loadBalancerAdmin`, and the 5-permission `model_garden_deployer` custom role avoids granting broad roles like `roles/aiplatform.admin` or `roles/compute.networkAdmin`.
- **PSC PrivateEndpoint Prediction Calls (`google-cloud-aiplatform[private_endpoints]`):**
  - `aiplatform.PrivateEndpoint(endpoint_name=ENDPOINT_ID).predict(instances=[...], endpoint_override=ENDPOINT_IP_ADDRESS)` sends an HTTPS POST directly to `https://<ENDPOINT_IP_ADDRESS>/v1/projects/<PROJECT_ID>/locations/<REGION>/endpoints/<ENDPOINT_ID>:predict` over the PSC forwarding rule. Ensure `google-cloud-aiplatform[private_endpoints]` is installed so `urllib3` is available.
- **Container Lockfiles (`uv.lock`):**
  - [`1-apps/apps/chat/Dockerfile`](./1-apps/apps/chat/Dockerfile) runs `uv sync --locked`. Whenever `pyproject.toml` is updated, run `uv lock` in [`1-apps/apps/chat`](./1-apps/apps/chat) and commit the updated `uv.lock`.
