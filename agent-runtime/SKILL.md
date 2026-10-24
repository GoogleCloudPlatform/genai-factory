---
name: agent-runtime
description: Actionable runbook for configuring, deploying, customizing, and operating the agent-runtime factory (Vertex AI Agent Engine runtime with ADK and A2A agents, Private Service Connect Interface networking, Secure Web Proxy internet egress, and Firestore session/task persistence). Use this skill whenever a user asks to deploy or configure agent-runtime, switch between the ADK and A2A sample agents, configure PSC-I or Agent Gateway governance, update agent code on Vertex AI Agent Engine, or troubleshoot GOOGLE_CLOUD_LOCATION and Firestore session errors.
---

# Agent Runtime — Deployment & Operations Runbook

This skill guides you through configuring, deploying, customizing, and troubleshooting the [`agent-runtime`](./README.md) factory: a **Vertex AI Agent Engine (Reasoning Engine)** deployment running **Google ADK** or **ADK + A2A** agents with **Private Service Connect Interface (PSC-I)** private networking, a **Secure Web Proxy (SWP)** for controlled outbound internet egress, and a **Firestore (`FIRESTORE_NATIVE`)** database for persistent ADK sessions, artifacts, memories, and A2A task state.

> [!NOTE]
> For repository contributor workflows (regenerating `plan_summary.py` test inventories and running `pytest`), also consult [`agent-runtime/AGENTS.md`](./AGENTS.md).

______________________________________________________________________

## 1. Shared Skills Reference (Do Not Duplicate)

This factory relies on the repository's shared skills in [`../.agents/skills/`](../.agents/skills/README.md) for cross-cutting workflows. Always load the relevant shared skill first:

| Workflow Area | Shared Skill | How `agent-runtime` Uses It |
| :--- | :--- | :--- |
| **Stage 0 (`0-prereqs`), BYO-VPC, Fabric FAST, & `*.rep.googleapis.com` PSC/DNS** | [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) | Deploys Host (`gf-ar-hp-0`) & Service (`gf-ar-0`) projects, Shared VPC, PSC-I network attachment (`na-0`), Secure Web Proxy (`proxy-0`), and regional PSC endpoint (`aiplatform.<eu\|us>.rep.googleapis.com`). |
| **Impersonation Quota Fixes, Networking Debugging & Clean Teardown** | [`operations-and-teardown`](../.agents/skills/operations-and-teardown/SKILL.md) | Resolves `403 serviceusage.services.use`, `aiplatform.<eu\|us>.rep.googleapis.com` timeouts, and cleans up generated `1-apps` files. |

______________________________________________________________________

## 2. Factory-Specific Resource & Identity Identifiers

When applying the patterns in [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md), use these exact `agent-runtime` identifiers:

- **Default Resource Name (`var.name` in `1-apps`):** `"agent-0"` (used for both the Vertex AI Reasoning Engine and the `FIRESTORE_NATIVE` database).
- **Stage 0 Project YAML Templates:**
  - Service project (`gf-ar-0`): [`0-prereqs/data/projects/service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)
  - Host project (`gf-ar-hp-0`): [`0-prereqs/data/projects/host.yaml`](./0-prereqs/data/projects/host.yaml)
- **Required `service_account_emails` Map Keys in `1-apps`:**
  - `"service-01/iac-rw"` — Stage 1 Terraform deployer SA (`<prefix>-gf-ar-0-rw@...`, holds `roles/aiplatform.user`, `roles/datastore.owner`, `roles/storage.admin`, `roles/viewer`).
  - `"service-01/gf-ar-0"` — Custom Agent Runtime execution SA (`<prefix>-gf-ar-0-ar@...`, holds `roles/aiplatform.user`, `roles/datastore.user`, `roles/modelarmor.user`, `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/cloudtrace.agent`).
- **Required Host Project Networking & IAM Grants (`0-prereqs/networking.tf` & `host.yaml`):**
  - **PSC-I Network Attachment:** `google_compute_network_attachment.network_attachment` (`connection_preference = "ACCEPT_MANUAL"` with `lifecycle { ignore_changes = [producer_accept_lists] }` because the Vertex AI service agent automatically populates the tenant project ID).
  - **Secure Web Proxy:** `module.secure-web-proxy` at `10.0.0.100:443` (passed to `1-apps` as `var.proxy_config = { ip_address = "10.0.0.100", port = 443 }`). An explicit proxy is required for Agent Engine instances using PSC-I to reach external internet APIs (such as `api.frankfurter.dev` in the sample currency agent).
  - **Service Agent Roles on Host Project:** `roles/compute.networkAdmin` for the host `aiplatform` service agent and `roles/dns.peer` for the `service-01/aiplatform` service agent (required for `dns_peering_configs` so the Agent Engine tenant network resolves the host VPC's Cloud DNS zones).

______________________________________________________________________

## 3. Step-by-Step Deployment Workflow

### Step 1: Run Stage 0 (`0-prereqs`)

Follow [`prerequisites-and-fast`](../.agents/skills/prerequisites-and-fast/SKILL.md) in [`0-prereqs/`](./0-prereqs/README.md). This generates `1-apps/providers.tf` and `1-apps/terraform.auto.tfvars` (including `network_attachment_id` and `proxy_config`).

### Step 2: Configure Stage 1 (`1-apps`) — Choose ADK or ADK + A2A

`1-apps` uses the Cloud Foundation Fabric `geap-agent-runtime` module with `managed = false` ([`1-apps/main.tf`](./1-apps/main.tf)) so Terraform provisions the Agent Engine runtime and initial code bundle once, while ongoing code updates can be pushed independently via CI/CD or the `commands` output.

#### Recipe A: Default Google ADK Agent (`./apps/adk`)

No extra variables are required beyond `terraform.auto.tfvars` from Stage 0:

```shell
cd 1-apps
terraform init
terraform apply
```

#### Recipe B: Google ADK + A2A Agent (`./apps/adk-a2a`)

To deploy the Agent2Agent (A2A) protocol agent ([`1-apps/apps/adk-a2a/`](./1-apps/apps/adk-a2a/README.md)), set `agent_runtime_config.class_methods` and `source_config.app_path` in `1-apps/terraform.tfvars` (or via `-var`):

```hcl
agent_runtime_config = {
  class_methods = "apps/adk-a2a/class-methods.json"
}

source_config = {
  app_path = "./apps/adk-a2a"
}
```

#### Recipe C: Attaching an Agent Gateway (`ge-agent-platform`)

You can set `var.agent_gateway_ids` (`egress` and/or `ingress`) from the [`ge-agent-platform`](../ge-agent-platform/SKILL.md) factory output:

```hcl
agent_gateway_ids = {
  egress = "projects/<project-id>/locations/<region>/agentGateways/<gateway-name>"
}
```

> [!WARNING]
> **Two API Constraints Apply to `agent_gateway_ids`:**
>
> 1. **PSC-I and Agent Gateway are mutually exclusive:** Setting `agent_gateway_ids` automatically disables `psc_interface_config` in [`1-apps/main.tf`](./1-apps/main.tf); the agent reaches your VPC via the gateway's connectivity template instead.
> 2. **`AGENT_IDENTITY` requirement:** The Vertex AI API currently rejects `agent_gateway_config` when the Reasoning Engine uses `identity_type = "SERVICE_ACCOUNT"` (`Reasoning Engine with 'agent_gateway_config' must use 'AGENT_IDENTITY' identity type`). See [`1-apps/README.md`](./1-apps/README.md) before enabling `agent_gateway_ids`.

### Step 3: Deploy / Update Agent Code & Query the Agent

1. View the generated update and test commands:

   ```shell
   terraform output -raw commands
   ```

2. **How Code Updates Work (`managed = false`):**

   - By default, `module.agent` sets `managed = false` so local changes to `apps/adk/` or `apps/adk-a2a/` do not force Terraform to recreate the Reasoning Engine on every `terraform apply`.
   - To update the running Agent Engine instance with new Python code **without Terraform**, run the `tar -czf - ... | base64` + `curl -X PATCH` command printed by `terraform output -raw commands`.
   - To force **Terraform** to re-upload the archive and replace the unmanaged Reasoning Engine resource:
     ```shell
     rm -f *.tar.gz
     terraform apply -replace="module.agent.google_vertex_ai_reasoning_engine.unmanaged[0]"
     ```

3. **Querying the Deployed Agent:**

   - **ADK Agent (`apps/adk`):** Follow [`1-apps/apps/adk/README.md`](./1-apps/apps/adk/README.md) (`:query` for session creation and `:streamQuery` for streaming tool-assisted responses).
   - **A2A Agent (`apps/adk-a2a`):** Follow [`1-apps/apps/adk-a2a/README.md`](./1-apps/apps/adk-a2a/README.md) (`GET /v1beta1/.../reasoningEngines/<id>/a2a/v1/card` for the Agent Card and `POST .../a2a/v1/message:send` for A2A task execution).

______________________________________________________________________

## 4. Customizing Agents & Architecture Gotchas

### 1. `GOOGLE_CLOUD_LOCATION` Is a Reserved Environment Variable on Agent Engine

- Vertex AI Agent Engine **rejects** `GOOGLE_CLOUD_LOCATION` in `spec.deploymentSpec.env` during Reasoning Engine creation/update.
- However, newer Gemini models (`gemini-3-flash-preview` / `gemini-4-argon`) are served on multi-regional endpoints (`eu` or `us`), and `google-adk` / `google-genai` read `GOOGLE_CLOUD_LOCATION` from `os.environ`.
- **Pattern Used in `apps/adk` and `apps/adk-a2a`:**
  1. [`1-apps/main.tf`](./1-apps/main.tf) passes `REGION = var.region` (e.g., `europe-west1`) via `environment_variables` for `vertexai.init(project=..., location=config.REGION)`.
  2. [`src/config.py`](./1-apps/apps/adk/src/config.py) computes `GOOGLE_CLOUD_LOCATION = "eu" if REGION.startswith("europe") else "us"`.
  3. [`agent.py`](./1-apps/apps/adk/agent.py) explicitly sets `os.environ["GOOGLE_CLOUD_LOCATION"] = config.GOOGLE_CLOUD_LOCATION` at module import time **and** inside `session_service_builder()` / `_init_adk()`. Preserve this pattern whenever customizing `agent.py`.

### 2. Outbound Internet Calls Under PSC-I Require the Secure Web Proxy (`PROXY_ADDRESS`)

- When `ENABLE_PSC_I` is enabled (`true` by default), the Agent Engine container has no direct internet access.
- Any external HTTP/HTTPS calls made by agent tools (such as `requests.get("https://api.frankfurter.dev/...")` in `get_exchange_rate`) must route through `http://{config.PROXY_ADDRESS}:{config.PROXY_PORT}` (`10.0.0.100:443`) and the destination host must be allowed in `0-prereqs` `networking_config.proxy_config.policy_rules`.

### 3. Firestore Session, Artifact, Memory, and Task Services

- Both sample agents persist state in the regional `FIRESTORE_NATIVE` database named `var.name` (`FIRESTORE_DATABASE`, default `"agent-0"`):
  - `apps/adk/src/firestore_session_service.py` — ADK `SessionService` backed by Firestore.
  - `apps/adk-a2a/src/firestore_{session,artifact,memory}_service.py` and `firestore_task_store.py` — Full ADK + A2A `TaskStore` persistence in Firestore.
- Ensure the custom Agent Runtime SA (`service-01/gf-ar-0`) retains `roles/datastore.user` in the service project.

### 4. Well-Known A2A Agent Card Route (`WellKnownCardA2aAgent`)

- When integrating an Agent Engine A2A agent with **Gemini Enterprise (`ge-agent-platform`)** or external A2A clients that probe `/.well-known/agent-card.json`, keep the `WellKnownCardA2aAgent` subclass in [`1-apps/apps/adk-a2a/agent.py`](./1-apps/apps/adk-a2a/agent.py), which registers `/.well-known/agent-card.json` and `/a2a/.well-known/agent-card.json` on the Reasoning Engine FastAPI router.
