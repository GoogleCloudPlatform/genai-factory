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

# This bucket is used to store resources during import/export operations
resource "google_storage_bucket" "build" {
  project                     = var.project_config.id
  name                        = "${var.prefix}-${var.name}-build"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = !var.enable_deletion_protection
}

resource "google_discovery_engine_data_store" "knowledge_base" {
  data_store_id                = "${var.name}-kb"
  display_name                 = "${var.name} knowledge base"
  project                      = var.project_config.id
  location                     = var.region_ai_applications
  industry_vertical            = "GENERIC"
  content_config               = "CONTENT_REQUIRED"
  solution_types               = ["SOLUTION_TYPE_CHAT"]
  skip_default_schema_creation = true

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
  project       = var.project_config.id
  location      = var.region_ai_applications
  data_store_id = google_discovery_engine_data_store.knowledge_base.data_store_id
  json_schema   = file("./data/knowledge-base/knowledge_base_data_store_schema.json")
}

resource "google_ces_app" "gecx_as_app" {
  app_id       = "${var.name}-app"
  display_name = "${var.name} App"
  project      = var.project_config.id
  location     = var.region_ai_applications
  description  = "A sample Gemini Enterprise for CX application."

  language_settings {
    default_language_code = var.gecx_as_configs.supported_languages[0]
    supported_language_codes = (
      slice(
        var.gecx_as_configs.supported_languages,
        1,
        length(var.gecx_as_configs.supported_languages)
    ))
    enable_multilingual_support = false
  }

  audio_processing_config {
    dynamic "synthesize_speech_configs" {
      for_each = toset(var.gecx_as_configs.supported_languages)

      content {
        language_code = synthesize_speech_configs.value
        speaking_rate = var.gecx_as_configs.speaking_rate
      }
    }
  }

  logging_settings {
    cloud_logging_settings {
      enable_cloud_logging = var.gecx_as_configs.enable_cloud_logging
    }
  }

  time_zone_settings {
    time_zone = var.gecx_as_configs.timezone
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
