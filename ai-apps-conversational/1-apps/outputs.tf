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
  _dialogflow_apis      = "dialogflow.googleapis.com"
  _discoveryengine_apis = "discoveryengine.googleapis.com"
  agent_dir             = "./build/agent/dist"
  uris_prefix = (
    var.region_ai_applications == null || var.region_ai_applications == "global"
    ? ""
    : "${var.region_ai_applications}-"
  )
  uris = {
    agent  = "${local.uris_prefix}${local._dialogflow_apis}/v3/${module.dialogflow.chat_engines["dialogflow"].chat_engine_metadata[0].dialogflow_agent}:restore"
    ds_faq = "${local.uris_prefix}${local._discoveryengine_apis}/v1/${module.dialogflow.data_stores["faq"].name}/branches/0/documents:import"
    ds_kb  = "${local.uris_prefix}${local._discoveryengine_apis}/v1/${module.dialogflow.data_stores["kb"].name}/branches/0/documents:import"
  }
}

output "commands" {
  description = "Run these commands to complete the deployment."
  value       = <<EOT
  # Run these commands to complete the deployment.
  # Alternatively, deploy the agent through your CI/CD pipeline.

  # Get token impersonating iac-rw SA
  export BEARER_TOKEN=$(gcloud auth print-access-token --impersonate-service-account iac-rw@lp-gf-ai-apps-df-0.iam.gserviceaccount.com)

  # Load faq data into the data store
  gcloud storage cp ./data/ds-faq/* ${module.ds-bucket.url}/ds-faq/ \
    --impersonate-service-account ${var.service_accounts["project/iac-rw"].email} &&
  curl -X POST ${local.uris.ds_faq} \
    -H "Authorization: Bearer $BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${var.project_config.id}" \
    -d '{
      "autoGenerateIds": true,
      "gcsSource":{
        "inputUris":["${module.ds-bucket.url}/ds-faq"],
        "dataSchema":"csv"
      },
      "reconciliationMode":"FULL"
    }'

  # Load kb data into the data store
  uv run ./tools/agentutil process_data_store_documents \
    ./data/ds-kb/ \
    ./build/data/ds-kb/ \
    ${module.ds-bucket.url}/ds-kb/ \
    --upload &&
  curl -X POST ${local.uris.ds_kb} \
    -H "Authorization: Bearer $BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${var.project_config.id}" \
    -d '{
      "gcsSource":{
        "inputUris":["${module.ds-bucket.url}/ds-kb/documents.jsonl"],
        "dataSchema":"document"
      },
      "reconciliationMode":"FULL"
    }'

  # Build and deploy agent variant
  rm -rf ${local.agent_dir}
  mkdir -p ${local.agent_dir}
  cp -r ./agents/${var.agent_configs.variant}/* ${local.agent_dir}
  uv run ./tools/agentutil replace_data_store \
    ${local.agent_dir} \
    "kb-and-faq" \
    UNSTRUCTURED \
    ${module.dialogflow.data_stores["kb"].name} &&
  cd ${local.agent_dir} &&
  zip -r agent.dist.zip * &&
  gcloud storage cp ${local.agent_dir}/agent.dist.zip ${module.build-bucket.url}/agents/agent-${var.agent_configs.variant}.dist.zip \
    --impersonate-service-account ${var.service_accounts["project/iac-rw"].email} &&
  curl -X POST ${local.uris.agent} \
    -H "Authorization: Bearer $BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${var.project_config.id}" \
    -d '{
      "agentUri": "${module.ds-bucket.url}"
    }'
  EOT
}
