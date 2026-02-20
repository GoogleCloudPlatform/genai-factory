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

output "commands" {
  description = "Run the following commands when the deployment completes to update and mange the application."
  value       = <<EOT
  # We wrote a variables.generated.env file in the scripts directory,
  # so you can run following commands.

  # Deploy the application
  uv run bash scripts/deploy_agent.sh

  # Ingest documents into the Knowledge Base
  uv run bash scripts/deploy_agent.sh --ingest-kb
  EOT
}

resource "local_file" "env_vars" {
  content  = <<-EOT
# This file is generated following terraform apply. It can be read by script to interact with the deployed resources

export BUILD_BUCKET="${google_storage_bucket.build.name}"
export GCP_PROJECT_ID="${var.project_config.id}"
export CES_APP_ID="${google_ces_app.gecx_as_app.app_id}"
export CES_APP_LOCATION="${google_ces_app.gecx_as_app.location}"
export KNOWLEDGE_BASE_DATA_STORE_ID="${google_discovery_engine_data_store.knowledge_base.data_store_id}"
export KNOWLEDGE_BASE_DATA_STORE_LOCATION="${google_discovery_engine_data_store.knowledge_base.location}"
export KNOWLEDGE_BASE_DATA_STORE_NAME="${google_discovery_engine_data_store.knowledge_base.name}"
EOT
  filename = "./scripts/variables.generated.env"
}
