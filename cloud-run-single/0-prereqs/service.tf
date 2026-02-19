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

module "projects" {
  source = "../../../cloud-foundation-fabric/modules/project-factory"
  # source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project-factory?ref=v53.0.0"
  data_defaults = {
    billing_account = var.project_config.billing_account_id
    parent          = var.project_config.parent
    prefix          = var.project_config.prefix
    bucket = {
      force_destroy = !var.enable_deletion_protection
    }
    locations = {
      storage = var.region
    }
  }
  factories_config = {
    basepath = "./data"
    paths = {
      projects = "projects/service"
    }
  }
}
