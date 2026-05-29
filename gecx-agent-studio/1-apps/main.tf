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

locals {
  bucket_name = coalesce(var.bucket_name, var.name)
  iam_principals = {
    for k, v in var.service_accounts
    : k => v.email
  }
}

module "build-bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v56.2.0"
  project_id    = var.project_id
  prefix        = var.prefix
  name          = "${local.bucket_name}-build"
  location      = var.region
  versioning    = true
  force_destroy = !var.enable_deletion_protection
}

resource "google_discovery_engine_data_store" "datastore" {
  for_each                     = var.datastores_configs
  data_store_id                = "${each.key}-ds"
  display_name                 = "${each.key} datastore"
  project                      = var.project_id
  location                     = var.region_discovery_engine
  industry_vertical            = each.value.industry_vertical
  content_config               = each.value.content_config
  solution_types               = each.value.solution_types
  skip_default_schema_creation = each.value.skip_default_schema_creation
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

resource "google_discovery_engine_schema" "datastore" {
  for_each      = var.datastores_configs
  schema_id     = "${each.key}-kb-schema"
  project       = var.project_id
  location      = var.region_discovery_engine
  data_store_id = google_discovery_engine_data_store.datastore[each.key].data_store_id
  json_schema   = file(each.value.schema_path)
  deletion_policy = (
    var.enable_deletion_protection
    ? "PREVENT"
    : "DELETE"
  )
}

resource "google_ces_app" "gecx_as_app" {
  for_each            = var.agents_configs
  app_id              = each.key
  display_name        = each.key
  project             = var.project_id
  location            = var.region_discovery_engine
  description         = "A sample Gemini Enterprise for CX application."
  tool_execution_mode = each.value.tool_execution_mode

  language_settings {
    default_language_code = each.value.supported_languages[0]
    supported_language_codes = (
      slice(
        each.value.supported_languages,
        1,
        length(each.value.supported_languages)
    ))
    enable_multilingual_support = false
  }

  audio_processing_config {
    dynamic "synthesize_speech_configs" {
      for_each = toset(each.value.supported_languages)

      content {
        language_code = synthesize_speech_configs.value
        speaking_rate = each.value.speaking_rate
      }
    }
  }

  logging_settings {
    cloud_logging_settings {
      enable_cloud_logging = each.value.enable_cloud_logging
    }
    conversation_logging_settings {
      disable_conversation_logging = !each.value.enable_conversation_logging
    }
  }

  time_zone_settings {
    time_zone = each.value.timezone
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
