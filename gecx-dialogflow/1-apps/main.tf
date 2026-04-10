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
}

module "ds-bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v54.3.0"
  project_id    = var.project_config.id
  prefix        = var.project_config.prefix
  name          = "${local.bucket_name}-ds"
  location      = var.regions.resources
  versioning    = true
  force_destroy = !var.enable_deletion_protection
}

module "build-bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v54.3.0"
  project_id    = var.project_config.id
  prefix        = var.project_config.prefix
  name          = "${local.bucket_name}-build"
  location      = var.regions.resources
  versioning    = true
  force_destroy = !var.enable_deletion_protection
}

# See https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/master/modules/ai-applications/variables.tf
# to learn how to customize this.
module "dialogflow" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/ai-applications?ref=v54.3.0"
  name       = var.name
  project_id = var.project_config.id
  location   = var.regions.agent
  data_stores_configs = {
    faq = {
      location       = var.regions.datastores
      content_config = "NO_CONTENT"
      solution_types = ["SOLUTION_TYPE_CHAT"]
    }
    kb = {
      location                     = var.regions.datastores
      content_config               = "CONTENT_REQUIRED"
      solution_types               = ["SOLUTION_TYPE_CHAT"]
      skip_default_schema_creation = true
      json_schema                  = file("./data/ds-kb/ds-kb-schema.json")
      document_processing_config = {
        chunking_config = {
          layout_based_chunking_config = {
            chunk_size                = 500
            include_ancestor_headings = true
          }
        }
        default_parsing_config = {
          layout_parsing_config = true
        }
        parsing_config_overrides = {}
      }
    }
  }
  engines_configs = {
    engine_location = var.regions.engine
    data_store_ids = [
      "faq",
      "kb"
    ]
    industry_vertical = "GENERIC"
    company_name      = "Cymbal"
    chat_engine_config = {
      agent_config = {
        location = var.regions.agent
      }
      allow_cross_region    = true
      default_language_code = "en-us"
      time_zone             = "Europe/Rome"
    }
  }
}
