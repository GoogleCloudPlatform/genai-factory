---
name: operations-and-teardown
description: >-
  Shared operational troubleshooting and clean teardown runbook across all
  genai-factory blueprints. Covers fixing gcloud service account impersonation
  quota project errors (403 serviceusage.services.use), diagnosing private
  networking timeouts on *.rep.googleapis.com, handling Serverless VPC IP
  reservation delays on destroy, and cleaning up Stage 0 generated files.
---

# Operational Troubleshooting & Clean Teardown (`operations-and-teardown`)

This shared skill provides the troubleshooting and teardown procedures common to all factories in `genai-factory`.

______________________________________________________________________

## 1. Common E2E Deployment Issues & Fixes

### Issue A — `gcloud` Commands Fail with `403 Permission 'serviceusage.services.use' denied`

- **Symptom**: Running `gcloud storage cp`, `gcloud artifacts repositories create`, `gcloud builds submit`, or `gcloud run deploy` with `--impersonate-service-account=<prefix>-...-iac-rw@...` fails with a `403` error on `serviceusage.services.use`.

- **Root Cause**: The local machine's `gcloud` configuration has `billing/quota_project` set to a different project where the impersonated Stage 1 `iac-rw` service account lacks permissions.

- **Fix**: Export `CLOUDSDK_BILLING_QUOTA_PROJECT` set to the Stage 1 service project ID (or unset `billing/quota_project`) before running deployment commands:

  ```shell
  export CLOUDSDK_BILLING_QUOTA_PROJECT="<service-project-id>"
  ```

### Issue B — Connection Timeouts or TLS Errors Calling Vertex AI or Model Armor (`*.rep.googleapis.com`)

- **Symptom**: Workloads with private VPC egress (`Cloud Run` with `PRIVATE_RANGES_ONLY` or `ALL_TRAFFIC`, or `Agent Engine` with PSC-I) hang or fail with TLS certificate errors when calling `aiplatform.<eu|us>.rep.googleapis.com` or `modelarmor.<region>.rep.googleapis.com`.
- **Root Cause**: Standard Private Google Access (`199.36.153.8/30` for `private.googleapis.com`) only routes global `*.googleapis.com` domains and does **not** route regional/multi-regional `.rep.googleapis.com` endpoints.
- **Fix**:
  - Verify that `google_network_connectivity_regional_endpoint` and `module.dns_policy_googleapis` in `0-prereqs/networking.tf` were applied for `var.region`.
  - If using an existing Shared VPC (`networking_config.create = false`), provision regional PSC endpoints and Cloud DNS response policy `A` records for `aiplatform.<eu|us>.rep.googleapis.com.` and `modelarmor.<region>.rep.googleapis.com.` in the host VPC.

### Issue C — Stage 1 Terraform or `gcloud` Fails Due to Missing API or Permission

- **Root Cause**: Because `1-apps` runs by impersonating the `service-01/iac-rw` service account created in `0-prereqs`, any API or IAM role needed by `1-apps` resources must be granted in `0-prereqs/data/projects/service-01.yaml` (or `host.yaml` for Shared VPC host resources).
- **Fix**: Add the missing API or IAM binding to `0-prereqs/data/projects/service-01.yaml` (or `host.yaml`) and re-apply `0-prereqs` before re-running `1-apps`.

______________________________________________________________________

## 2. Clean Teardown Procedure

Always tear down stages in reverse order (`1-apps` first, then `0-prereqs`):

1. **Disable deletion protection** (if `enable_deletion_protection = true` was used):

   - Set `enable_deletion_protection = false` in `1-apps/terraform.tfvars` (and `0-prereqs/terraform.tfvars`, which also updates `1-apps/terraform.auto.tfvars`) and run `terraform apply` before destroying.

2. **Empty stateful resources that block deletion** *(factory-specific)*:

   - In `cloud-run-rag-search`: delete all `DataObject` items from the Vector Search 2.0 Collection before running `terraform destroy` (`DeleteCollection` fails with `400 COLLECTION_HAS_DATA_OBJECTS` if non-empty).

3. **Destroy Stage 1 (`1-apps`)**:

   ```shell
   cd <factory>/1-apps && terraform destroy -auto-approve
   ```

4. **Destroy Stage 0 (`0-prereqs`) & Handle Serverless VPC IP Reservation Delay**:

   ```shell
   cd <factory>/0-prereqs && terraform destroy -auto-approve
   ```

   - **Note on `resourceInUseByAnotherResource` (`serverless-ipv4-cloudrun-*`)**: After destroying Cloud Run services or jobs that use Direct VPC Egress on a Shared VPC subnet, Google Cloud Serverless retains the `/28` internal IP reservation (`serverless-ipv4-cloudrun-*`) for several minutes. If `0-prereqs` `terraform destroy` fails while detaching the Shared VPC or deleting `sub-0`, wait 5–10 minutes for the reservation to release (or delete the service project first) and re-run `terraform destroy`.

5. **Clean Up Generated Handoff Files in `1-apps/`**:

   - Leaving the generated `1-apps/providers.tf` and `1-apps/terraform.auto.tfvars` files on disk causes `uv run pytest` and `uv run tools/plan_summary.py` to fail (because Terraform attempts to initialize the deleted remote GCS backend). Always remove them after E2E teardown:

     ```shell
     rm -rf <factory>/1-apps/providers.tf \
            <factory>/1-apps/terraform.auto.tfvars \
            <factory>/1-apps/terraform.tfvars \
            <factory>/1-apps/.terraform* \
            <factory>/0-prereqs/terraform.tfvars \
            <factory>/0-prereqs/.terraform* \
            <factory>/0-prereqs/terraform.tfstate*
     ```
