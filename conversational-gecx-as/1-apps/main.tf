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

resource "google_storage_bucket" "build" {
  project                     = var.project_config.id
  name                        = "${var.name}-build-${var.project_config.number}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = !var.enable_deletion_protection
}

resource "google_discovery_engine_data_store" "knowledge_base" {
  project           = var.project_config.id
  location          = var.region_ai_applications
  data_store_id     = "${var.name}-kb"
  display_name      = "[${var.name}] Knowledge Base"
  industry_vertical           = "GENERIC"
  content_config              = "CONTENT_REQUIRED"
  solution_types              = ["SOLUTION_TYPE_CHAT"]
  document_processing_config {
    default_parsing_config  {
      layout_parsing_config {
        enable_table_annotation = true
        enable_image_annotation = true
      }
    }
    chunking_config {
      layout_based_chunking_config {
        chunk_size = 500
        include_ancestor_headings = true
      }
    }
  }
  skip_default_schema_creation = true
}

resource "google_discovery_engine_schema" "knowledge_base" {
  project       = var.project_config.id
  location      = var.region_ai_applications
  data_store_id = google_discovery_engine_data_store.knowledge_base.data_store_id
  schema_id     = "${var.name}-kb-schema"
  json_schema   = file("knowledge_base_data_store_schema.json")
}

resource "google_ces_app" "ces_app" {
  project = var.project_config.id
  app_id = "${var.name}-agent"
  location = var.region_ai_applications
  description = "An example Gemini Enterprise for CX application"
  display_name = "[${var.name}] Agent"

  language_settings {
    default_language_code    = "en-US"
    supported_language_codes = ["fr-CA"]
    enable_multilingual_support = true
  }

  audio_processing_config {
    synthesize_speech_configs {
      language_code = "en-US"
      speaking_rate = 0
    }
    synthesize_speech_configs {
      language_code = "fr-CA"
      speaking_rate = 0
    }
  }

  logging_settings {
    cloud_logging_settings {
      enable_cloud_logging = true
    }
  }
  time_zone_settings {
    time_zone = "America/Los_Angeles"
  }

  lifecycle {
    # Updates after first apply will be controlled by the agent export itself
    ignore_changes = [
      root_agent,
      global_instruction,
      variable_declarations,
      data_store_settings,
      language_settings,
      pinned,
      guardrails
    ]
  }
}
