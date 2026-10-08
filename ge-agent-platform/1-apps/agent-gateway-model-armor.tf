# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# tfdoc:file:description Model Armor templates and floor settings.

locals {
  # The Agent Gateway only accepts Model Armor templates from its own region,
  # while an assistant needs them in the app location. The directions the
  # gateway binds therefore follow var.region, everything else var.location.
  modelarmor_assistant_directions = flatten([
    for app in values(var.gemini_enterprise_apps) : compact([
      app.assistant.model_armor.user_prompt_direction,
      app.assistant.model_armor.response_direction,
    ])
    if app.assistant.model_armor.enable
  ])
  modelarmor_gateway_directions = (
    var.agent_gateway_config.egress.model_armor_config.enable
    ? compact([
      var.agent_gateway_config.egress.model_armor_config.request_direction,
      var.agent_gateway_config.egress.model_armor_config.response_direction,
    ])
    : []
  )
  modelarmor_referenced_directions = toset(concat(
    local.modelarmor_gateway_directions,
    local.modelarmor_assistant_directions
  ))
  modelarmor_templates = {
    for k, v in var.model_armor_templates : k => merge(v, {
      location = (
        contains(local.modelarmor_gateway_directions, k)
        ? var.region
        : var.location
      )
    })
    if contains(local.modelarmor_referenced_directions, k)
  }
}

resource "google_model_armor_template" "default" {
  for_each        = local.modelarmor_templates
  project         = var.project_id
  location        = each.value.location
  template_id     = "${var.model_armor_template_prefix}${each.key}"
  deletion_policy = local.deletion_policy

  filter_config {
    rai_settings {
      dynamic "rai_filters" {
        for_each = each.value.rai_filters
        content {
          filter_type      = rai_filters.key
          confidence_level = rai_filters.value
        }
      }
    }

    sdp_settings {
      basic_config {
        filter_enforcement = each.value.sdp.enabled
      }
    }

    pi_and_jailbreak_filter_settings {
      filter_enforcement = each.value.pi_and_jailbreak.enabled
      confidence_level   = each.value.pi_and_jailbreak.confidence_level
    }

    malicious_uri_filter_settings {
      filter_enforcement = each.value.malicious_uri.enabled
    }
  }

  template_metadata {
    custom_llm_response_safety_error_code    = each.value.custom_llm_response_safety_error_code
    custom_llm_response_safety_error_message = each.value.custom_llm_response_safety_error_message
    custom_prompt_safety_error_code          = each.value.custom_prompt_safety_error_code
    custom_prompt_safety_error_message       = each.value.custom_prompt_safety_error_message
    enforcement_type                         = each.value.enforcement_type
    ignore_partial_invocation_failures       = each.value.ignore_partial_invocation_failures
    log_sanitize_operations                  = each.value.logging
    log_template_operations                  = each.value.logging

    multi_language_detection {
      enable_multi_language_detection = true
    }

    filter_version_selector {
      alias = "FILTER_VERSION_ALIAS_STABLE"
    }
  }
}

# google_model_armor_template (provider 8.4.0) does not support yet
# templateMetadata.modalities or templateMetadata.dataResidencyCompliant
# so we set them via local-exec provider
resource "terraform_data" "template_metadata_patch" {
  for_each = local.modelarmor_templates

  triggers_replace = {
    template = google_model_armor_template.default[each.key].name
    # Any change here means Terraform issues a PATCH carrying templateMetadata,
    # which clears both fields, so the patch has to run again after it.
    config = sha256(jsonencode(each.value))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -euo pipefail

      endpoint="https://modelarmor.${each.value.location}.rep.googleapis.com/v1"
      url="$endpoint/${google_model_armor_template.default[each.key].name}"
      mask="templateMetadata.modalities,templateMetadata.dataResidencyCompliant"
      body=$(mktemp)
      trap 'rm -f "$body"' EXIT

      status=$(curl -sS -X PATCH \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -H "X-Goog-User-Project: ${var.project_id}" \
        -d '${jsonencode({
    templateMetadata = {
      modalities             = each.value.modalities
      dataResidencyCompliant = true
    }
})}' \
        -o "$body" -w '%%{http_code}' \
        "$url?updateMask=$mask")

      if [[ "$status" != 2* ]]; then
        echo "Model Armor metadata patch failed for ${each.key} (HTTP $status)" >&2
        cat "$body" >&2
        exit 1
      fi
    EOT
}
}

resource "google_model_armor_floorsetting" "floorsetting" {
  count = (
    var.model_armor_floor_setting.enabled ? 1 : 0
  )
  location                         = "global"
  parent                           = "projects/${var.project_id}"
  enable_floor_setting_enforcement = true
  integrated_services              = ["AI_PLATFORM"]

  filter_config {
    rai_settings {
      dynamic "rai_filters" {
        for_each = var.model_armor_floor_setting.rai_filters
        content {
          filter_type      = rai_filters.key
          confidence_level = rai_filters.value
        }
      }
    }

    sdp_settings {
      basic_config {
        filter_enforcement = var.model_armor_floor_setting.sdp.enabled
      }
    }

    pi_and_jailbreak_filter_settings {
      filter_enforcement = var.model_armor_floor_setting.pi_and_jailbreak.enabled
      confidence_level   = var.model_armor_floor_setting.pi_and_jailbreak.confidence_level
    }

    malicious_uri_filter_settings {
      filter_enforcement = var.model_armor_floor_setting.malicious_uri.enabled
    }
  }

  ai_platform_floor_setting {
    inspect_only         = var.model_armor_floor_setting.enforcement_type == "INSPECT_ONLY" ? true : null
    inspect_and_block    = var.model_armor_floor_setting.enforcement_type == "INSPECT_AND_BLOCK" ? true : null
    enable_cloud_logging = var.model_armor_floor_setting.logging
  }

  floor_setting_metadata {
    multi_language_detection {
      enable_multi_language_detection = true
    }
  }
}
