---
name: discovery-engine-and-gecx
description: >-
  Shared runbook for provisioning and operating Vertex AI Search (Discovery
  Engine) data stores, document import workflows, and private Service Directory
  + Internal Regional TCP Proxy Load Balancer integrations for Gemini Enterprise
  and Customer Experience (GECX Agent Studio & Dialogflow CX) factories.
---

# Discovery Engine Data Stores & GECX Private Fulfillment (`discovery-engine-and-gecx`)

This shared skill covers patterns shared across `ai-apps-search`, `ge-agent-platform`, `gecx-agent-studio`, and `gecx-dialogflow`.

______________________________________________________________________

## 1. Unstructured & FAQ Discovery Engine Data Stores

1. **Document Processing Configuration**:
   - When provisioning an unstructured `google_discovery_engine_data_store` (`CONTENT_REQUIRED`), always ensure `document_processing_config` (including `default_parsing_config { digital_parsing_config {} }`) is configured on the resource so document import operations (`import_documents`) work immediately after `terraform apply`.
2. **Discovery Engine Service Agent Permissions**:
   - Before triggering `import_documents` from a GCS bucket, the Discovery Engine service agent (`service-<PROJECT_NUMBER>@gcp-sa-discoveryengine.iam.gserviceaccount.com`) must hold `roles/storage.objectViewer` on the source bucket (configured in `0-prereqs/data/projects/service-01.yaml`).
   - When using 3rd-party SaaS data connectors (`ge-agent-platform`) backed by Secret Manager secrets, the same service agent also requires `roles/secretmanager.viewer` and `roles/secretmanager.secretAccessor`.

______________________________________________________________________

## 2. Private Toolset & Webhook Access via Service Directory (`gecx-agent-studio` & `gecx-dialogflow`)

Both `gecx-agent-studio` (OpenAPI Cloud Run toolset) and `gecx-dialogflow` (2nd-gen Cloud Run Function webhook) expose private serverless backends to Dialogflow CX / CX Agent Studio without public internet exposure:

1. **Architecture Chain**:
   - `Dialogflow CX / Agent Studio` -> `Service Directory Service` -> `Internal Regional TCP Proxy Load Balancer` (`REGIONAL_MANAGED_PROXY` subnet) -> `Serverless NEG` -> `Cloud Run / Cloud Function` (with `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`).
2. **Mandatory Networking & IAM Prerequisites**:
   - **Proxy-Only Subnet**: The VPC in `var.region` must have a `REGIONAL_MANAGED_PROXY` subnet (`proxy-only-sub-0`, created by `0-prereqs/networking.tf`) for the Internal Regional TCP Proxy Load Balancer.
   - **Dialogflow Service Agent IAM**: The Dialogflow service agent (`service-<PROJECT_NUMBER>@gcp-sa-dialogflow.iam.gserviceaccount.com`) must be granted `roles/servicedirectory.viewer` and `roles/servicedirectory.pscAuthorizedService` in the service project (`0-prereqs/data/projects/service-01.yaml`) so it can traverse the Service Directory private network attachment.
