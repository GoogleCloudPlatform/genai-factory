---
name: genai-factory-prerequisites-and-fast
description: Use when deploying Stage 0 (0-prereqs) in genai-factory, attaching a Bring-Your-Own Shared VPC (networking_config.create = false), integrating 1-apps with Cloud Foundation Fabric FAST (variables-fast.tf), or configuring regional PSC endpoints and Cloud DNS response policies for *.rep.googleapis.com APIs.
---

# GenAI Factory Prerequisites, BYO-VPC & Fabric FAST

## Overview

Every `genai-factory` blueprint splits infrastructure into `0-prereqs` (projects, state buckets, least-privilege service accounts, Shared VPC, and private Google API routing) and `1-apps` (workload resources deployed by impersonating the Stage 0 `iac-rw` service account).

## When to Use

- Bootstrapping a factory via `0-prereqs` (with a new or existing Shared VPC).
- Wiring `1-apps` manually (without `0-prereqs`) or onto **Cloud Foundation Fabric FAST** (`variables-fast.tf`).
- Configuring private VPC routing for regional/multi-regional `*.rep.googleapis.com` APIs (`aiplatform.<eu|us>.rep.googleapis.com`, `modelarmor.<region>.rep.googleapis.com`).
- **REQUIRED SUB-SKILL for Teardown & Quota Issues:** Use [`genai-factory-operations-and-teardown`](../genai-factory-operations-and-teardown/SKILL.md).

## Quick Reference — Prerequisite Modes

| Mode | When to Choose | What Generates `1-apps` Inputs |
| :--- | :--- | :--- |
| **Mode A: `0-prereqs` (Default)** | New service project + new Shared VPC host project | `0-prereqs` writes `1-apps/providers.tf` & `1-apps/terraform.auto.tfvars` |
| **Mode B: `0-prereqs` + BYO-VPC** | New service project attached to an existing Shared VPC | `0-prereqs` with `networking_config.create = false` |
| **Mode C: Fabric FAST** | Projects/VPC managed by FAST `2-project-factory` | Copy `0-prereqs/data/projects/*.yaml` into FAST; drop FAST `*.auto.tfvars.json` into `1-apps/` |
| **Mode D: Custom / Manual** | Pre-existing projects and SAs outside `0-prereqs` | Manually create `1-apps/providers.tf` & `1-apps/terraform.tfvars` from `0-prereqs/templates/*.tpl` |

## Core Patterns

### Mode A: Standard `0-prereqs` (`0-prereqs/terraform.tfvars`)

```hcl
billing_account = "012345-6789AB-CDEF01"
parent          = "folders/1234567890" # or "organizations/1234567890"
prefix          = "myorg"              # <= 9 lowercase chars/digits
region          = "europe-west1"
```

### Mode B: Bring Your Own Shared VPC (`0-prereqs/terraform.tfvars`)

Requires `roles/compute.xpnAdmin` on the host project (or organizational folder) for the caller running `0-prereqs`:

```hcl
networking_config = {
  create       = false
  host_project = "my-existing-host-project-id"
  vpc_name     = "my-existing-shared-vpc"
  subnet = {
    name = "my-existing-subnet-name"
  }
  subnet_proxy_only = {
    name = "my-existing-proxy-only-subnet"
  }
}
```

### Mode C: Fabric FAST Integration (`1-apps/terraform.tfvars`)

Never edit `1-apps/variables-fast.tf`. Drop FAST `*.auto.tfvars.json` files into `1-apps/` and pass FAST map keys instead of raw resource IDs:

```hcl
networking_config = {
  vpc    = "dev-spoke-0"
  subnet = "dev-spoke-0/europe-west1/default-ew1"
}

service_account_emails = {
  "service-01/iac-rw"       = "service-01/iac-rw"
  "service-01/crun-0"       = "service-01/crun-0"
  "service-01/crun-build-0" = "service-01/crun-build-0"
}
```

### Regional & Multi-Regional `*.rep.googleapis.com` Routing

`private.googleapis.com` (`199.36.153.8/30`) does **not** route `*.rep.googleapis.com`. Private VPC workloads require a `google_network_connectivity_regional_endpoint` (`access_type = "REGIONAL"`) plus a Cloud DNS Response Policy A-record in the host VPC:

- Multi-regional Vertex AI (`gemini-3-flash-preview` / `gemini-4-argon`): `aiplatform.${startswith(var.region, "europe") ? "eu" : "us"}.rep.googleapis.com`
- Regional Model Armor: `modelarmor.${var.region}.rep.googleapis.com`
- Requires `networkconnectivity.googleapis.com` enabled and `roles/networkconnectivity.regionalEndpointAdmin` on `service-01/iac-rw` in `0-prereqs/data/projects/host.yaml`.

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| TLS cert mismatch or timeout on `*.rep.googleapis.com` in BYO-VPC | `private.googleapis.com` wildcard DNS intercepts `.rep.googleapis.com` without a regional PSC endpoint | Provision `google_network_connectivity_regional_endpoint` + Cloud DNS response policy rule in the BYO host VPC |
| `403 Permission denied` during `1-apps` `terraform apply` | Missing API or IAM role on Stage 0 `service-01/iac-rw` | Add the API/role to `0-prereqs/data/projects/service-01.yaml` (or `host.yaml`) and re-apply `0-prereqs` |
| `pytest` or `plan_summary.py` fails with GCS backend error | `0-prereqs` generated `1-apps/providers.tf` and `terraform.auto.tfvars` left on disk | Remove `1-apps/providers.tf` and `1-apps/terraform.auto.tfvars` after E2E teardown |
