---
name: prerequisites-and-fast
description: >-
  Shared runbook for configuring and deploying Stage 0 (0-prereqs) across
  genai-factory blueprints, attaching to an existing Bring-Your-Own Shared VPC
  (networking_config.create = false), integrating Stage 1 (1-apps) directly with
  Cloud Foundation Fabric FAST (variables-fast.tf), and configuring regional PSC
  endpoints and Cloud DNS response policies for *.rep.googleapis.com APIs.
---

# Prerequisites, Shared VPC & Fabric FAST Integration (`prerequisites-and-fast`)

This shared skill covers the three prerequisite strategies used across `genai-factory` blueprints and the private networking requirements for regional/multi-regional Google APIs.

> [!NOTE]
> Always check the target factory's `SKILL.md` (and `0-prereqs/data/projects/*.yaml`) for the exact project suffixes, service account keys, and required regional APIs before executing one of the workflows below.

______________________________________________________________________

## 1. Choosing a Prerequisite Strategy

Every factory in this repository is split into `0-prereqs` (project creation, IAM delegation, and optional Shared VPC setup) and `1-apps` (platform and workload deployment). Choose one of three modes:

### Option A — Full Standalone (`0-prereqs` + `1-apps`)

Use when starting from a GCP Organization or Folder without pre-existing project or VPC infrastructure.

1. **Required caller permissions**:

   - `roles/resourcemanager.projectCreator` on `project_config.parent` (`folders/<id>` or `organizations/<id>`).
   - `roles/billing.user` on `project_config.billing_account_id`.

2. **What `0-prereqs` provisions**:

   - Reads YAML definitions in `0-prereqs/data/projects/` via the Cloud Foundation Fabric `project-factory` module:
     - `service-01.yaml`: Creates the service project, enables workload APIs, provisions the `<prefix>-...-iac-state` GCS bucket for Stage 1 Terraform state, and creates the Stage 1 automation service account (`service-01/iac-rw`) plus workload service accounts.
     - `host.yaml` *(in factories with VPC networking)*: Creates the Shared VPC host project, attaches `service-01` as a Shared VPC service project, and provisions the VPC (`net-0`), primary subnet (`sub-0`), proxy-only subnet (`proxy-only-sub-0`), Cloud DNS response policies for Private Google Access (`private.googleapis.com`), and regional PSC endpoints (`0-prereqs/networking.tf`).

3. **Execution**:

   - Create `0-prereqs/terraform.tfvars` from `0-prereqs/terraform.tfvars.sample`:

     ```hcl
     prefix = "myorg"
     project_config = {
       billing_account_id = "012345-6789AB-CDEF01"
       parent             = "folders/1234567890"
     }
     region                     = "europe-west1"
     enable_deletion_protection = false # Set false for test/ephemeral environments
     ```

   - Run `terraform init && terraform apply` inside `0-prereqs/`.

4. **Handoff Verification**:

   - Confirm that `0-prereqs` generated two files inside `../1-apps/`:
     - `1-apps/providers.tf` (configured to impersonate `service-01/iac-rw` and store state in `service-01/iac-state`).
     - `1-apps/terraform.auto.tfvars` (populating `project_id`, `region`, `networking_config`, `service_account_emails`, `service_account_ids`, etc.).

### Option B — Bring Your Own Shared VPC (`networking_config.create = false` in `0-prereqs`)

Use when `0-prereqs` should create the service project and service accounts, but attach to an existing Shared VPC host project.

1. **Configure `0-prereqs/terraform.tfvars`**:

   ```hcl
   prefix = "myorg"
   project_config = {
     billing_account_id = "012345-6789AB-CDEF01"
     parent             = "folders/1234567890"
   }
   region = "europe-west1"
   networking_config = {
     create          = false
     host_project_id = "existing-host-project-id"
     vpc_name        = "existing-vpc-name"
     subnet = {
       name = "existing-subnet-name"
     }
   }
   ```

2. **Checklist of Prerequisites on the Existing Host Project**:

   - **Shared VPC attachment & Subnet IAM**: Attach the newly created `service-01` project to the Shared VPC host project and grant `roles/compute.networkUser` on the host project/subnet to the required service agents (e.g., Cloud Run Service Agent `service-<PROJECT_NUMBER>@serverless-robot-prod.iam.gserviceaccount.com`, or `service-01/iac-rw` when creating internal addresses/PSC forwarding rules).
   - **Proxy-only subnet**: If the factory deploys an Internal Application Load Balancer (`lbs_configs.internal.enable = true`) or an Internal Regional TCP Proxy Load Balancer (for GECX Service Directory), ensure a `REGIONAL_MANAGED_PROXY` subnet exists in `var.region`.
   - **Database / Agent Engine Private Connectivity**:
     - For `cloud-run-rag-alloydb` and `cloud-run-rag-cloudsql`: Stage 1 creates a Private Service Connect (PSC) consumer endpoint and binds a private Cloud DNS zone to the Shared VPC (`1-apps/database.tf`), so `service-01/iac-rw` must have `roles/compute.networkUser` and `roles/dns.admin` on the Shared VPC host project.
     - For `agent-runtime`: ensure a Private Service Connect Interface (PSC-I) network attachment (`google_compute_network_attachment`) exists in the subnet.
   - **Regional PSC endpoints for `*.rep.googleapis.com`**: See [Section 2](#2-private-networking-for-regional-and-multi-regional-apis-repgoogleapiscom) below.

### Option C — Fabric FAST or Custom Prerequisite Pipeline (Skip `0-prereqs`)

Use when projects, Shared VPCs, and service accounts are managed outside this repository (e.g., via Cloud Foundation Fabric FAST `2-networking` and `2-project-factory`).

1. **Project Factory YAML reuse**: You can copy `0-prereqs/data/projects/service-01.yaml` directly into your FAST `2-project-factory` stage so all required APIs, service accounts, and IAM bindings are created consistently.
2. **Prepare `1-apps/providers.tf`**: Create `1-apps/providers.tf` modeled on `0-prereqs/templates/providers.tf.tpl`.
3. **Wire FAST `.auto.tfvars.json` via `variables-fast.tf`**:
   - Every factory's `1-apps/variables-fast.tf` declares `service_accounts`, `vpc_self_links`, and `subnet_self_links` matching FAST output files.

   - Drop FAST's exported `.auto.tfvars.json` files into `1-apps/`, then reference the map keys (or provide literal resource IDs/emails) in `1-apps/terraform.tfvars`:

     ```hcl
     project_id = "my-service-project-id"
     region     = "europe-west1"

     networking_config = {
       vpc    = "prod-landing"              # Key in var.vpc_self_links or full VPC self-link
       subnet = "europe-west1/prod-default" # Key in var.subnet_self_links or full subnet ID
     }

     service_account_emails = {
       # Map each factory's expected key (see 1-apps/variables.tf) to a key in var.service_accounts or a literal email:
       "service-01/iac-rw" = "service-01/iac-rw"
     }

     service_account_ids = {
       "service-01/iac-rw" = "service-01/iac-rw"
     }
     ```

   - Never edit `1-apps/variables-fast.tf`.

______________________________________________________________________

## 2. Private Networking for Regional and Multi-Regional APIs (`*.rep.googleapis.com`)

- **Why Private Google Access (`private.googleapis.com`) is not enough**:
  - The standard Private Google Access VIPs (`199.36.153.8/30`) and wildcard DNS records (`*.googleapis.com`) only route global Google APIs.
  - Regional and multi-regional endpoints (`<service>.<location>.rep.googleapis.com`) are **not** routed by `private.googleapis.com` and will fail with connection timeouts or TLS certificate mismatches from private VPC workloads unless a dedicated regional PSC endpoint (`google_network_connectivity_regional_endpoint`) and Cloud DNS response policy rule exist in the VPC.
- **Multi-Regional Vertex AI (`aiplatform.<eu|us>.rep.googleapis.com`) vs. Regional APIs**:
  - Newer Gemini models (e.g., `gemini-4-argon`) are served on multi-regional Vertex AI endpoints (`eu` when `region` starts with `europe`, otherwise `us`), while infrastructure services such as Model Armor (`modelarmor.<region>.rep.googleapis.com`) remain strictly regional.
  - When `networking_config.create = true`, `0-prereqs/networking.tf` automatically provisions regional PSC endpoints and DNS response policy rules for the `.rep.googleapis.com` endpoints required by that factory.
  - When `networking_config.create = false` (BYO-VPC) or using FAST, ensure equivalent `google_network_connectivity_regional_endpoint` resources and DNS response policy rules are present in your host VPC.
