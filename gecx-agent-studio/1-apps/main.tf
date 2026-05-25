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

# To store agent app src during its deployment
# when using agentutil
module "build_bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v56.0.0"
  project_id    = var.project_id
  prefix        = var.prefix
  name          = "${var.name}-build"
  location      = var.region
  force_destroy = !var.enable_deletion_protection
}

resource "google_discovery_engine_data_store" "knowledge_base" {
  data_store_id                = "${var.name}-kb"
  display_name                 = "${var.name} knowledge base"
  project                      = var.project_id
  location                     = var.region_discovery_engine
  industry_vertical            = "GENERIC"
  content_config               = "CONTENT_REQUIRED"
  solution_types               = ["SOLUTION_TYPE_CHAT"]
  skip_default_schema_creation = true
  deletion_policy = (
    var.enable_deletion_protection
    ? "PREVENT"
    : "DELETE"
  )

  document_processing_config {
    default_parsing_config {
      layout_parsing_config {
        enable_image_annotation = true
        enable_table_annotation = true
      }
    }
    chunking_config {
      layout_based_chunking_config {
        chunk_size                = 500
        include_ancestor_headings = true
      }
    }
  }
}

resource "google_discovery_engine_schema" "knowledge_base" {
  schema_id     = "${var.name}-kb-schema"
  project       = var.project_id
  location      = var.region_discovery_engine
  data_store_id = google_discovery_engine_data_store.knowledge_base.data_store_id
  json_schema   = file("./data/ds-kb/knowledge_base_data_store_schema.json")
  deletion_policy = (
    var.enable_deletion_protection
    ? "PREVENT"
    : "DELETE"
  )
}

resource "google_ces_app" "gecx_as_app" {
  app_id              = var.name
  display_name        = var.name
  project             = var.project_id
  location            = var.region_discovery_engine
  description         = "A sample Gemini Enterprise for CX application."
  tool_execution_mode = var.cx_as_configs.tool_execution_mode

  language_settings {
    default_language_code = var.cx_as_configs.supported_languages[0]
    supported_language_codes = (
      slice(
        var.cx_as_configs.supported_languages,
        1,
        length(var.cx_as_configs.supported_languages)
    ))
    enable_multilingual_support = false
  }

  audio_processing_config {
    dynamic "synthesize_speech_configs" {
      for_each = toset(var.cx_as_configs.supported_languages)

      content {
        language_code = synthesize_speech_configs.value
        speaking_rate = var.cx_as_configs.speaking_rate
      }
    }
  }

  logging_settings {
    cloud_logging_settings {
      enable_cloud_logging = var.cx_as_configs.enable_cloud_logging
    }
    conversation_logging_settings {
      disable_conversation_logging = !var.cx_as_configs.enable_conversation_logging
    }
  }

  time_zone_settings {
    time_zone = var.cx_as_configs.timezone
  }

  lifecycle {
    # After the first apply, agent export will control updates
    ignore_changes = [
      description,
      data_store_settings,
      global_instruction,
      guardrails,
      language_settings,
      pinned,
      root_agent,
      variable_declarations,
      audio_processing_config,
      time_zone_settings,
    ]
  }
}
