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

# Model Armor service extension.
resource "google_network_services_authz_extension" "ma_authz_srv_ext" {
  count     = var.agent_gateway_config.model_armor_config.enable ? 1 : 0
  name      = "${var.name}-ma"
  project   = var.project_id
  location  = var.region
  service   = "modelarmor.${var.region}.rep.googleapis.com"
  timeout   = var.agent_gateway_config.model_armor_config.timeout
  fail_open = var.agent_gateway_config.model_armor_config.fail_open
  metadata = {
    "model_armor_settings" = jsonencode([{
      request_template_id  = google_model_armor_template.request[0].name
      response_template_id = google_model_armor_template.response[0].name
    }])
  }
}

# Create a policy to bind the service extension to egress Agent Gateway.
resource "google_network_security_authz_policy" "ma_authz_policy" {
  count          = var.agent_gateway_config.model_armor_config.enable ? 1 : 0
  name           = "${var.name}-ma"
  project        = var.project_id
  location       = var.region
  policy_profile = "CONTENT_AUTHZ"
  action         = "CUSTOM"

  target {
    resources = [module.agent_gateway.id]
  }

  custom_provider {
    authz_extension {
      resources = [
        google_network_services_authz_extension.ma_authz_srv_ext[0].id
      ]
    }
  }

  dynamic "http_rules" {
    for_each = (
      length(var.agent_gateway_config.model_armor_config.authz_hosts) > 0
      ? [1] : []
    )
    content {
      to {
        operations {
          dynamic "hosts" {
            for_each = var.agent_gateway_config.model_armor_config.authz_hosts
            content {
              exact = hosts.value
            }
          }
        }
      }
    }
  }

  depends_on = [
    time_sleep.wait_for_gateway,
    google_network_security_authz_policy.iap_authz_policy
  ]
}

# RAI + PI/jailbreak + malicious URI + SDP
resource "google_model_armor_template" "request" {
  count       = var.agent_gateway_config.model_armor_config.enable ? 1 : 0
  project     = var.project_id
  location    = var.region
  template_id = var.model_armor_template_config.request_template_id

  filter_config {
    rai_settings {
      dynamic "rai_filters" {
        for_each = var.model_armor_template_config.rai_filters
        content {
          filter_type      = rai_filters.key
          confidence_level = rai_filters.value
        }
      }
    }

    sdp_settings {
      basic_config {
        filter_enforcement = var.model_armor_template_config.sdp.enabled
      }
    }

    pi_and_jailbreak_filter_settings {
      filter_enforcement = var.model_armor_template_config.pi_and_jailbreak.enabled
      confidence_level   = var.model_armor_template_config.pi_and_jailbreak.confidence_level
    }

    malicious_uri_filter_settings {
      filter_enforcement = var.model_armor_template_config.malicious_uri.enabled
    }
  }

  template_metadata {
    custom_llm_response_safety_error_code    = 401
    custom_llm_response_safety_error_message = "This is a custom error message for LLM response"
    custom_prompt_safety_error_code          = 400
    custom_prompt_safety_error_message       = "This is a custom error message for prompt"
    enforcement_type                         = var.model_armor_template_config.enforcement_type
    ignore_partial_invocation_failures       = true
    log_template_operations                  = var.model_armor_template_config.logging
    log_sanitize_operations                  = var.model_armor_template_config.logging

    multi_language_detection {
      enable_multi_language_detection = true
    }
  }
}

# RAI + PI/jailbreak + malicious URI + SDP
resource "google_model_armor_template" "response" {
  count       = var.agent_gateway_config.model_armor_config.enable ? 1 : 0
  project     = var.project_id
  location    = var.region
  template_id = var.model_armor_template_config.response_template_id

  filter_config {
    rai_settings {
      dynamic "rai_filters" {
        for_each = var.model_armor_template_config.rai_filters
        content {
          filter_type      = rai_filters.key
          confidence_level = rai_filters.value
        }
      }
    }

    sdp_settings {
      basic_config {
        filter_enforcement = var.model_armor_template_config.sdp.enabled
      }
    }

    pi_and_jailbreak_filter_settings {
      filter_enforcement = var.model_armor_template_config.pi_and_jailbreak.enabled
      confidence_level   = var.model_armor_template_config.pi_and_jailbreak.confidence_level
    }

    malicious_uri_filter_settings {
      filter_enforcement = var.model_armor_template_config.malicious_uri.enabled
    }
  }

  template_metadata {
    custom_llm_response_safety_error_code    = 401
    custom_llm_response_safety_error_message = "This is a custom error message for LLM response"
    custom_prompt_safety_error_code          = 400
    custom_prompt_safety_error_message       = "This is a custom error message for prompt"
    enforcement_type                         = var.model_armor_template_config.enforcement_type
    ignore_partial_invocation_failures       = true
    log_sanitize_operations                  = var.model_armor_template_config.logging
    log_template_operations                  = var.model_armor_template_config.logging

    multi_language_detection {
      enable_multi_language_detection = true
    }
  }
}

resource "google_model_armor_floorsetting" "floorsetting" {
  count = (
    var.model_armor_template_config.floor_setting.enabled ? 1 : 0
  )
  location                         = "global"
  parent                           = "projects/${var.project_id}"
  enable_floor_setting_enforcement = true
  integrated_services              = ["AI_PLATFORM"]

  filter_config {
    rai_settings {
      dynamic "rai_filters" {
        for_each = var.model_armor_template_config.floor_setting.rai_filters
        content {
          filter_type      = rai_filters.key
          confidence_level = rai_filters.value
        }
      }
    }

    sdp_settings {
      basic_config {
        filter_enforcement = var.model_armor_template_config.floor_setting.sdp.enabled
      }
    }

    pi_and_jailbreak_filter_settings {
      filter_enforcement = var.model_armor_template_config.floor_setting.pi_and_jailbreak.enabled
      confidence_level   = var.model_armor_template_config.floor_setting.pi_and_jailbreak.confidence_level
    }

    malicious_uri_filter_settings {
      filter_enforcement = var.model_armor_template_config.floor_setting.malicious_uri.enabled
    }
  }

  ai_platform_floor_setting {
    inspect_only         = var.model_armor_template_config.floor_setting.enforcement_type == "INSPECT_ONLY" ? true : null
    inspect_and_block    = var.model_armor_template_config.floor_setting.enforcement_type == "INSPECT_AND_BLOCK" ? true : null
    enable_cloud_logging = var.model_armor_template_config.floor_setting.logging
  }

  floor_setting_metadata {
    multi_language_detection {
      enable_multi_language_detection = true
    }
  }
}
