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

locals {
  _dialogflow_apis      = "dialogflow.googleapis.com/v3"
  _discoveryengine_apis = "discoveryengine.googleapis.com/v1"
  _env_vars = [
    "PROJECT_ID=${var.project_config.id}",
    "REGION=${var.region}",
  ]
  agent_dir = "./build/agent/dist"
  env_vars  = join(",", local._env_vars)
  uris = {
    agent  = "https://${var.region}-${local._dialogflow_apis}/${module.dialogflow.chat_engines["dialogflow"].chat_engine_metadata[0].dialogflow_agent}:restore"
    ds_faq = "https://${var.region}-${local._discoveryengine_apis}/${module.dialogflow.data_stores["faq"].name}/branches/0/documents:import"
    ds_kb  = "https://${var.region}-${local._discoveryengine_apis}/${module.dialogflow.data_stores["kb"].name}/branches/0/documents:import"
  }
}

output "commands" {
  description = "Run these commands to complete the deployment."
  value       = <<EOT
  # Run these commands to complete the deployment.
  # Alternatively, deploy the agent through your CI/CD pipeline.

  # Load faq data into the data store
  gcloud storage cp ./data/ds-faq/* ${module.ds-bucket.url}/ds-faq/ &&
  curl -X POST ${local.uris.ds_faq} \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${var.project_config.id}" \
    -d '{
      "autoGenerateIds": true,
      "gcsSource":{
        "inputUris":["${module.ds-bucket.url}"],
        "dataSchema":"csv"
      },
      "reconciliationMode":"FULL"
    }'

  # Load kb data into the data store
  ./tools/agentutil process_data_store_documents \
    ./data/ds-kb/ \
    ./build/data/ds-kb/ \
    ${module.ds-bucket.url}/ds-kb/ \
    --upload &&
  curl -X POST ${local.uris.ds_kb} \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${var.project_config.id}" \
    -d '{
      "autoGenerateIds": true,
      "gcsSource":{
        "inputUris":["${module.ds-bucket.url}/documents.jsonl"],
        "dataSchema":"document"
      },
      "reconciliationMode":"FULL"
    }'

  # Build agent variant
  rm -rf ${local.agent_dir}
  mkdir -p ${local.agent_dir}
  cp -r ./agents/${var.agent_configs.variant}/* ${local.agent_dir}

  # Generate configuration from templates and Terraform outputs
  agentutil replace_data_store \
    ${local.agent_dir} \
    "knowledge-base-and-faq" \
    UNSTRUCTURED \
    $KNOWLEDGE_BASE_DATA_STORE_NAME &&
  cd ${local.agent_dir} &&
  zip -r agent.dist.zip * &&
  gcloud storage cp ${local.agent_dir}/agent.dist.zip ${module.build-bucket.url}/agents/agent-${var.agent_configs.variant}.dist.zip &&
  curl -X POST ${local.uris.agent} \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${var.project_config.id}" \
    -d '{
      "agentUri": "${module.ds-bucket.url}"
    }'
  EOT
}

# resource "local_file" "env_vars" {
#   content  = <<-EOT
# GCP_PROJECT_ID="${var.gcp_project_id}"
# AGENT_VARIANT="${var.agent_variant}"
# AGENT_REMOTE="${var.agent_remote}"
# AGENT_LOCATION="${element(split("/", google_discovery_engine_chat_engine.agent.chat_engine_metadata[0].dialogflow_agent), 3)}"
# BUILD_BUCKET="${google_storage_bucket.build.name}"
# KNOWLEDGE_BASE_DATA_STORE_LOCATION="${google_discovery_engine_data_store.knowledge_base.location}"
# KNOWLEDGE_BASE_DATA_STORE_ID="${google_discovery_engine_data_store.knowledge_base.data_store_id}"
# KNOWLEDGE_BASE_DATA_STORE_NAME="${google_discovery_engine_data_store.knowledge_base.name}"
# FAQ_DATA_STORE_NAME="${google_discovery_engine_data_store.structured_faq.name}"
# AGENT_ID="${google_discovery_engine_chat_engine.agent.engine_id}"
# AGENT_NAME="${google_discovery_engine_chat_engine.agent.name}"
# DIALOGFLOW_AGENT="${google_discovery_engine_chat_engine.agent.chat_engine_metadata[0].dialogflow_agent}"
# EOT
#   filename = "${path.module}/variables.generated.env"
# }
