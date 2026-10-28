---
name: genai-factory-model-armor
description: Use when configuring Google Cloud Model Armor templates (model_armor_template_config, model_armor_templates) or project floor settings (model_armor_floorsetting_config, model_armor_floor_setting) in genai-factory, tuning SDP/PI/RAI filter confidence levels, or troubleshooting regional modality errors such as Image modality unsupported in europe-west1.
---

# GenAI Factory Model Armor Configuration

## Overview

Configures regional Google Cloud Model Armor templates (`google_model_armor_template`) and project-level Vertex AI floor settings (`google_model_armor_floorsetting`) across `cloud-run-single`, `serve-private-models`, and `ge-agent-platform`.

## When to Use

- Tuning prompt injection (`pi_and_jailbreak`), Sensitive Data Protection (`sdp`), malicious URI (`malicious_uri`), or Responsible AI (`rai_filters`) thresholds in `1-apps/terraform.tfvars`.
- Switching Model Armor between `INSPECT_AND_BLOCK` and audit-only `INSPECT_ONLY`.
- Debugging regional capability errors on Model Armor templates or private VPC timeouts on `modelarmor.<region>.rep.googleapis.com`.

## Quick Reference — Filter & Enforcement Values

| Setting | Allowed Values | Default |
| :--- | :--- | :--- |
| `enforcement_type` | `"INSPECT_AND_BLOCK"`, `"INSPECT_ONLY"` | `"INSPECT_AND_BLOCK"` |
| `sdp.enabled`, `malicious_uri.enabled`, `pi_and_jailbreak.enabled` | `"ENABLED"`, `"DISABLED"` | `"ENABLED"` |
| `pi_and_jailbreak.confidence_level`, `rai_filters.*` | `"LOW_AND_ABOVE"`, `"MEDIUM_AND_ABOVE"`, `"HIGH"` | `"HIGH"` (`"LOW_AND_ABOVE"` / `"MEDIUM_AND_ABOVE"` in `ge-agent-platform`) |
| `rai_filters` keys | `HATE_SPEECH`, `DANGEROUS`, `HARASSMENT`, `SEXUALLY_EXPLICIT` | All 4 enabled |

## Core Patterns

### Pattern 1: Single-App Factories (`cloud-run-single`, `serve-private-models`)

```hcl
model_armor_template_config = {
  enabled          = true
  enforcement_type = "INSPECT_AND_BLOCK"
  logging          = true
  sdp              = { enabled = "ENABLED" }
  malicious_uri    = { enabled = "ENABLED" }
  pi_and_jailbreak = {
    enabled          = "ENABLED"
    confidence_level = "MEDIUM_AND_ABOVE"
  }
  rai_filters = {
    HATE_SPEECH       = "MEDIUM_AND_ABOVE"
    DANGEROUS         = "MEDIUM_AND_ABOVE"
    HARASSMENT        = "MEDIUM_AND_ABOVE"
    SEXUALLY_EXPLICIT = "HIGH"
  }
}

model_armor_floorsetting_config = {
  enabled          = true
  enforcement_type = "INSPECT_ONLY"
}
```

### Pattern 2: Directional Templates in `ge-agent-platform`

`ge-agent-platform` defines directional templates in `var.model_armor_templates` and only creates a template when referenced by an assistant (`assistant.model_armor.enable = true`) or the Egress Agent Gateway (`agent_gateway_config.egress.model_armor_config.enable = true`):

- **Assistant directions (`user-to-ge`, `ge-to-user`):** Created in `var.location` (`eu`, `us`, `global`); support `["MODALITY_TEXT", "MODALITY_IMAGE"]`.
- **Agent Gateway directions (`agent-gateway-to-external`, `external-to-agent-gateway`):** Created in `var.region` (`europe-west1`); must use `modalities = ["MODALITY_TEXT"]`.

## Common Mistakes

| Symptom / Error | Cause | Fix |
| :--- | :--- | :--- |
| `Region europe-west1 does not support the requested capabilities: Image modality` | Regional endpoints (`europe-west1`) do not support `MODALITY_IMAGE` | Set `modalities = ["MODALITY_TEXT"]` on regional Agent Gateway templates; never share a direction key between an assistant and the Agent Gateway |
| Connection timeout or TLS mismatch calling `modelarmor.<region>.rep.googleapis.com` | `private.googleapis.com` does not route regional `.rep.googleapis.com` endpoints | Provision a regional PSC endpoint and Cloud DNS response policy rule for `modelarmor.<region>.rep.googleapis.com` (see [`genai-factory-prerequisites-and-fast`](../genai-factory-prerequisites-and-fast/SKILL.md)) |
