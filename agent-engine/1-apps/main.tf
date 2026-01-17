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

data "archive_file" "source" {
  type        = "tar.gz"
  source_dir  = "./apps/adk"
  output_path = "./source.tar.gz"
}

module "agent" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/agent-engine?ref=v51.0.0"
  name       = var.name
  project_id = var.project_config.id
  region     = var.region
  managed    = false
  agent_engine_config = {
    agent_framework = var.agent_engine_config.agent_framework
    class_methods   = var.agent_engine_config.class_methods
  }
  bucket_config = {
    deletion_protection = var.enable_deletion_protection
    name                = "${var.prefix}-${var.name}"
  }
  deployment_files = {
    source_config = {
      entrypoint_module = "agent"
      entrypoint_object = "agent"
      source_path       = data.archive_file.source.output_path
    }
  }
  service_account_config = {
    create = false
    email  = var.service_accounts["project/gf-ae-0"].email
  }
}
