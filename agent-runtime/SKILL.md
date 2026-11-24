---
name: genai-factory-agent-runtime
description: Use when deploying or configuring the genai-factory agent-runtime blueprint on Vertex AI Agent Engine (Reasoning Engine), switching between the ADK and ADK + A2A sample agents, configuring PSC-I network attachments or Secure Web Proxy egress, attaching an Agent Gateway, or troubleshooting GOOGLE_CLOUD_LOCATION and Firestore session errors.
---

# GenAI Factory — Agent Runtime (`agent-runtime`)

## Overview

Deploys a **Vertex AI Agent Engine (Reasoning Engine)** runtime ([`agent-runtime`](./README.md)) running **Google ADK** (`apps/adk`) or **ADK + A2A** (`apps/adk-a2a`) agents with **Private Service Connect Interface (PSC-I)** networking, a **Secure Web Proxy (SWP)** for controlled outbound internet egress, and a regional **`FIRESTORE_NATIVE`** database for persistent sessions, artifacts, memories, and A2A tasks.

## When to Use

- Deploying or customizing [`0-prereqs/`](./0-prereqs/README.md) or [`1-apps/`](./1-apps/README.md) in `agent-runtime`.
- Switching between `apps/adk` and `apps/adk-a2a`, pushing code updates (`managed = false`), or attaching an Agent Gateway (`agent_gateway_ids`).
- **REQUIRED SUB-SKILL:** Load [`genai-factory-prerequisites-and-fast`](../.agents/skills/genai-factory-prerequisites-and-fast/SKILL.md) for Stage 0 (`0-prereqs`), BYO Shared VPC, Fabric FAST, and `aiplatform.<eu|us>.rep.googleapis.com` PSC/DNS setup.
- **REQUIRED SUB-SKILL:** Load [`genai-factory-operations-and-teardown`](../.agents/skills/genai-factory-operations-and-teardown/SKILL.md) for `CLOUDSDK_BILLING_QUOTA_PROJECT`, `.rep.googleapis.com` debugging, and clean teardown.
- For contributor test inventory workflows (`plan_summary.py` / `pytest`), see [`AGENTS.md`](./AGENTS.md).

## Quick Reference

| Attribute | Value / Definition |
| :--- | :--- |
| **Projects (`0-prereqs`)** | Service: `gf-ar-0` ([`service-01.yaml`](./0-prereqs/data/projects/service-01.yaml)); Host: `gf-ar-hp-0` ([`host.yaml`](./0-prereqs/data/projects/host.yaml)) |
| **Default Name (`var.name`)** | `agent-0` (used for both Reasoning Engine and `FIRESTORE_NATIVE` database) |
| **Required SA Keys (`1-apps`)** | `service-01/iac-rw` (deployer, with a delegated `projectIamAdmin` limited to the agent roles) |
| **Agent Identity (`1-apps`)** | `identity_type = "AGENT_IDENTITY"`; the module grants `datastore.user` and `storage.objectViewer` to the identity; `agent_identity` output is the `principal://` value |
| **Host Networking (`0-prereqs`)** | PSC-I `network_attachment` (`ACCEPT_MANUAL`, `ignore_changes = [producer_accept_lists]`), SWP `10.0.0.100:443`, host `aiplatform` SA `compute.networkAdmin`, `service-01/aiplatform` SA `dns.peer` |

## Core Patterns

### Switch to ADK + A2A Agent (`1-apps/terraform.tfvars`)

Default `1-apps` deploys `./apps/adk`. To deploy the A2A agent ([`1-apps/apps/adk-a2a/`](./1-apps/apps/adk-a2a/README.md)):

```hcl
agent_runtime_config = {
  class_methods = "apps/adk-a2a/class-methods.json"
}
source_config = {
  app_path = "./apps/adk-a2a"
}
```

### Attach an Agent Gateway (`ge-agent-platform`)

```hcl
agent_gateway_ids = {
  egress = "projects/<project-id>/locations/<region>/agentGateways/<gateway-name>"
}
```

### Push Code Updates & Query Agent

`module.agent` sets `managed = false` ([`1-apps/main.tf`](./1-apps/main.tf)) so local code edits do not recreate the Reasoning Engine on `terraform apply`.

```shell
# Print tar+base64 PATCH update command and curl query commands
terraform output -raw commands

# Or force Terraform to replace the unmanaged Reasoning Engine
rm -f *.tar.gz
terraform apply -replace="module.agent.google_vertex_ai_reasoning_engine.unmanaged[0]"
```

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| Reasoning Engine rejects `GOOGLE_CLOUD_LOCATION` in `env` | `GOOGLE_CLOUD_LOCATION` is reserved by Vertex AI Agent Engine | Pass `REGION` via Terraform env vars and set `os.environ["GOOGLE_CLOUD_LOCATION"] = "eu" if REGION.startswith("europe") else "us"` inside [`agent.py`](./1-apps/apps/adk/agent.py) at import time and in `session_service_builder()` / `_init_adk()`. |
| Outbound HTTP tool calls time out under PSC-I | PSC-I instances have no direct internet access | Route external requests through `http://{config.PROXY_ADDRESS}:{config.PROXY_PORT}` (`10.0.0.100:443`) and allow the target host in `0-prereqs` `networking_config.proxy_config.policy_rules`. |
| `Reasoning Engine with 'agent_gateway_config' must use 'AGENT_IDENTITY'` | `agent_gateway_ids` set on an agent deployed with `identity_type = "SERVICE_ACCOUNT"` | Keep the stage default `identity_type = "AGENT_IDENTITY"` in [`1-apps/main.tf`](./1-apps/main.tf). |
| Agent gets `PERMISSION_DENIED` on Firestore right after the first deploy | Roles are granted to the agent identity after the Reasoning Engine is created and take time to propagate | Wait a few minutes and retry. |
| External A2A client gets `404` on `/.well-known/agent-card.json` | Default A2A router only mounts under `/a2a/v1/card` | Keep the `WellKnownCardA2aAgent` subclass in [`1-apps/apps/adk-a2a/agent.py`](./1-apps/apps/adk-a2a/agent.py). |
| A2A request fails with `Authenticated caller principal is required` or `404` on `tasks/{id}` | `apps/adk-a2a` binds sessions and tasks to the verified `Authorization: Bearer` / IAP principal on `ServerCallContext` (ignoring `message.metadata.user_id`) | Send a valid Google OIDC/OAuth2 Bearer token (or authenticated `ServerCallContext.user`) and query tasks using the same caller identity that created them. |
