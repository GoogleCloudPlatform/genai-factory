# Copyright 2025 Google LLC
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

# See https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/master/modules/ai-applications/variables.tf
# to learn how to customize this.
module "ai-apps" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/ai-applications?ref=v43.0.0"
  name       = var.name
  project_id = var.project_config.id
  location   = var.region_ai_applications
  data_stores_configs = {
    ds = {
      content_config              = "PUBLIC_WEBSITE"
      create_advanced_site_search = false
      solution_types              = ["SOLUTION_TYPE_SEARCH"]
      sites_search_config = {
        target_sites = var.ai_apps_configs.target_sites
      }
    }
  }
  engines_configs = {
    app = {
      data_store_ids = [
        "ds"
      ]
      industry_vertical = "GENERIC"
      search_engine_config = {
        search_tier = "SEARCH_TIER_ENTERPRISE"
      }
    }
  }
}
