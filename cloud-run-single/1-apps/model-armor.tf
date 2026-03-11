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

resource "google_model_armor_template" "model_armor_template" {
  count = var.model_armor_config.enabled ? 1 : 0
  project     = var.project_config.id
  location    = var.region
  template_id = "model-armor-template"

  filter_config {
    rai_settings {
      dynamic "rai_filters" {
        for_each = var.model_armor_config.rai_filters
        content {
          filter_type      = rai_filters.key
          confidence_level = rai_filters.value
        }
      }
    }
    sdp_settings {
      basic_config {
        filter_enforcement = var.model_armor_config.sdp.enabled
      }
    }
    pi_and_jailbreak_filter_settings {
      filter_enforcement = var.model_armor_config.pi_and_jailbreak.enabled
      confidence_level   = var.model_armor_config.pi_and_jailbreak.confidence_level
    }
    malicious_uri_filter_settings {
      filter_enforcement = var.model_armor_config.malicious_uri.enabled
    }
  }

  template_metadata {
    custom_llm_response_safety_error_message = "This is a custom error message for LLM response"
    log_template_operations                  = var.model_armor_config.logging
    log_sanitize_operations                  = var.model_armor_config.logging
    ignore_partial_invocation_failures       = true
    custom_prompt_safety_error_code          = 400
    custom_prompt_safety_error_message       = "This is a custom error message for prompt"
    custom_llm_response_safety_error_code    = 401
    enforcement_type                         = var.model_armor_config.enforcement_type

    multi_language_detection {
      enable_multi_language_detection = true
    }
  }
}
