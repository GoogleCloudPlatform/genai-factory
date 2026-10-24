---
name: model-armor
description: >-
  Shared runbook for configuring Google Cloud Model Armor templates and project
  floor settings (SDP, malicious URI, prompt injection & jailbreak, RAI filters,
  enforcement types, and regional modality constraints) across genai-factory
  blueprints.
---

# Model Armor Configuration & Integration (`model-armor`)

This shared skill covers configuring and troubleshooting Google Cloud Model Armor across factories that sanitize prompts, responses, agents, and MCP tools (`cloud-run-single`, `serve-private-models`, `agent-runtime`, and `ge-agent-platform`).

______________________________________________________________________

## 1. Regional Templates vs. Project Floor Settings

Factories typically provision two distinct Model Armor resources (`model-armor.tf` or `agent-gateway-model-armor.tf`):

1. **Regional Model Armor Template (`google_model_armor_template`)**:
   - Created in `var.region` (e.g., `europe-west1`).
   - Used explicitly by application code (via the `MODEL_ARMOR_TEMPLATE` environment variable calling `modelarmor.<region>.rep.googleapis.com`) or attached to Agent Engine / Agent Gateways.
2. **Project-Level Floor Setting (`google_model_armor_floorsetting`)**:
   - Created at `projects/<project_id>/locations/global/floorSetting` with `integrated_services = ["AI_PLATFORM"]`.
   - Enforces baseline safety filters automatically across Vertex AI (`aiplatform`) calls in the project.

______________________________________________________________________

## 2. Standard `terraform.tfvars` Configuration (`cloud-run-single` & `serve-private-models`)

Both `model_armor_template_config` and `model_armor_floorsetting_config` accept the same schema and validation rules:

- `enabled`: `true` (default) or `false`.
- `enforcement_type`: `"INSPECT_AND_BLOCK"` (default) or `"INSPECT_ONLY"`.
- `logging`: `true` (default) or `false`.
- `sdp.enabled`, `malicious_uri.enabled`, `pi_and_jailbreak.enabled`: `"ENABLED"` (default) or `"DISABLED"`.
- Confidence levels (`pi_and_jailbreak.confidence_level` and `rai_filters.{HATE_SPEECH,DANGEROUS,HARASSMENT,SEXUALLY_EXPLICIT}`): `"LOW_AND_ABOVE"`, `"MEDIUM_AND_ABOVE"`, or `"HIGH"` (default).

```hcl
model_armor_template_config = {
  enabled          = true
  enforcement_type = "INSPECT_AND_BLOCK"
  logging          = true
  sdp = {
    enabled = "ENABLED"
  }
  malicious_uri = {
    enabled = "ENABLED"
  }
  pi_and_jailbreak = {
    enabled          = "ENABLED"
    confidence_level = "MEDIUM_AND_ABOVE"
  }
  rai_filters = {
    HATE_SPEECH       = "MEDIUM_AND_ABOVE"
    DANGEROUS         = "MEDIUM_AND_ABOVE"
    HARASSMENT        = "MEDIUM_AND_ABOVE"
    SEXUALLY_EXPLICIT = "MEDIUM_AND_ABOVE"
  }
}

model_armor_floorsetting_config = {
  enabled = false # Disable if you only want explicit template-level sanitization
}
```

______________________________________________________________________

## 3. Common Gotchas & Networking Requirements

1. **Regional PSC Endpoint Required for Private Workloads**:
   - Model Armor is a strictly regional API (`modelarmor.<region>.rep.googleapis.com`).
   - Workloads running with private VPC egress (`Cloud Run` with Direct VPC Egress or `Agent Engine` with PSC-I) require a `google_network_connectivity_regional_endpoint` and Cloud DNS response policy rule for `modelarmor.<region>.rep.googleapis.com` in `0-prereqs/networking.tf`.
2. **Service Account IAM**:
   - The workload service account (`crun-0` or `sa-agent-runtime-01`) and the Vertex AI service agent (`service-<PROJECT_NUMBER>@gcp-sa-aiplatform.iam.gserviceaccount.com`) require `roles/modelarmor.user` to invoke Model Armor templates.
   - Stage 1 `iac-rw` requires `roles/modelarmor.admin` and `roles/modelarmor.floorSettingsAdmin`.
3. **Regional Modality Support (`ge-agent-platform`)**:
   - In `ge-agent-platform`, Model Armor templates are patched via REST with `templateMetadata.modalities`. Regional endpoints such as `europe-west1` only support `["MODALITY_TEXT"]`; passing `MODALITY_IMAGE` or `MODALITY_AUDIO` in unsupported regions causes `400 INVALID_ARGUMENT`.
