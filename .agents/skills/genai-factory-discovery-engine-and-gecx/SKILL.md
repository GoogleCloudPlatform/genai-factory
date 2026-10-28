---
name: genai-factory-discovery-engine-and-gecx
description: Use when configuring Vertex AI Search (Discovery Engine) data stores or wiring private Service Directory and Internal Regional TCP Proxy Load Balancers in genai-factory (ai-apps-search, gecx-agent-studio, gecx-dialogflow, ge-agent-platform).
---

# GenAI Factory Discovery Engine & GECX Private Fulfillment

## Overview

Covers cross-cutting **Discovery Engine (Vertex AI Search)** location/schema conventions and the **Service Directory + Internal Regional TCP Proxy Load Balancer** private fulfillment architecture shared across `ai-apps-search`, `gecx-agent-studio`, `gecx-dialogflow`, and `ge-agent-platform`.

## When to Use

- Configuring `region_discovery_engine` / `location` (`eu`, `us`, `global`) alongside regional `region` (`europe-west1`) resources.
- Exposing private Cloud Run services, 2nd Gen Cloud Run Functions, or on-premises IPs to CX Agent Studio (`google_ces_app`) or Dialogflow CX over Service Directory (`service_directory_configs`).
- Troubleshooting TLS/CA certificate validation (`allowed_ca_certs`) or PSC authorization on Service Directory endpoints.

## Quick Reference — Location & Service Agent Rules

| Component | Location Variable | Required Service Agent Grants |
| :--- | :--- | :--- |
| Discovery Engine Data Stores, Search Engines, CES Apps | `region_discovery_engine` / `location` (`"eu"`, `"us"`, `"global"`) | `discoveryengine` SA: `roles/secretmanager.secretAccessor` (when using MCP/SaaS secrets) |
| Private Cloud Run / Cloud Functions, Internal Regional TCP Proxy LB, Service Directory | `region` (e.g., `"europe-west1"`) | `ces` or `dialogflow` SA: `roles/servicedirectory.viewer` + `roles/servicedirectory.pscAuthorizedService` (on host project); `iac-rw`: `roles/servicedirectory.networkAttacher` (on host project) |

## Core Patterns

### Why Internal Regional TCP Proxy LB Is Required for Service Directory

GECX (`ces.googleapis.com` and `dialogflow.googleapis.com`) reaches private backends via **Service Directory Private Network Access (PSC)**. It cannot target a Serverless NEG directly, so `gecx-agent-studio` and `gecx-dialogflow` chain:

`Service Directory Endpoint` -> `Internal Regional TCP Proxy LB Forwarding Rule IP:443` -> `Serverless NEG (Cloud Run / Cloud Function)` or `Hybrid Connectivity NEG (on-prem IP:port)`

### Configuring `service_directory_configs` (`1-apps/terraform.tfvars`)

```hcl
service_directory_configs = {
  example-com = {
    cloud_dns_domain = "example.com"
    endpoints = {
      "onprem/onprem-01" = {
        address   = "10.0.0.2"
        port      = 443
        create_lb = true # Wraps the IP:port in an Internal Regional TCP Proxy LB
      }
    }
    services = {
      onprem = {
        endpoints    = ["onprem-01"]
        openapi_spec = "data/onprem/openapi-spec.yaml" # gecx-agent-studio only
      }
    }
  }
}
```

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| TLS handshake or `allowed_ca_certs` rejection in CES / Dialogflow CX | Certificate provided in PEM format or SAN mismatch | Provide the CA certificate in binary **DER** format (base64-encoded DER bytes) and ensure the cert SAN matches `<service_name>.<cloud_dns_domain>` |
| `403 Permission denied` when CES / Dialogflow connects to Service Directory | Missing host project PSC/Service Directory roles | Grant `roles/servicedirectory.pscAuthorizedService` to the `ces`/`dialogflow` service agent and `roles/servicedirectory.networkAttacher` to `iac-rw` in `0-prereqs/data/projects/host.yaml` |
| Wrong API hostname in `curl` requests | Mixing regional (`europe-west1-`) and multi-regional (`eu-`) prefixes | Use `<region_discovery_engine>-discoveryengine.googleapis.com` for Discovery Engine imports and `<region>-dialogflow.googleapis.com` for Dialogflow CX |
