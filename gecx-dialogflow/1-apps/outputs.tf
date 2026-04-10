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
  _dialogflow_agent_id  = module.dialogflow.chat_agent_id
  _dialogflow_apis      = "https://${local.uris_prefix_agent}dialogflow.googleapis.com"
  _discoveryengine_apis = "https://${local.uris_prefix_ds}discoveryengine.googleapis.com"
  agent_dir             = "./build/agent/dist"
  uris_prefix_agent = (
    var.regions.agent == null || var.regions.agent == "global"
    ? ""
    : "${var.regions.agent}-"
  )
  uris_prefix_ds = (
    var.regions.datastores == null || var.regions.datastores == "global"
    ? ""
    : "${var.regions.datastores}-"
  )
  uris = {
    agent       = "${local._dialogflow_apis}/v3/${local._dialogflow_agent_id}:restore"
    agent_query = "${local._dialogflow_apis}/v3/${local._dialogflow_agent_id}/environments/draft/sessions/any-session-id:detectIntent"
    ds_faq      = "${local._discoveryengine_apis}/v1/${module.dialogflow.data_stores["faq"].name}/branches/0/documents:import"
    ds_kb       = "${local._discoveryengine_apis}/v1/${module.dialogflow.data_stores["kb"].name}/branches/0/documents:import"
  }
  webhooks = merge(
    {
      function = {
        uri = module.cloud_function.uri
      }
    },
    {
      for k, v in module.service_directory.service_id
      : "sd-${k}" => {
        allowed_ca_certs  = var.service_directory_configs.services[k].allowed_ca_certs
        service_directory = v
        uri               = "${module.service_directory.service_names[k]}.${var.service_directory_configs.cloud_dns_domain}"
      }
    }
  )
}

output "commands" {
  description = "Run these commands to complete the deployment."
  value = templatefile("./templates/outputs.sh", {
    agent_dir        = local.agent_dir
    agent_language   = var.agent_configs.language
    agent_region     = var.regions["agent"]
    agent_uri        = local.uris["agent"]
    agent_uri_query  = local.uris["agent_query"]
    agent_variant    = var.agent_configs.variant
    bucket_url_build = module.build-bucket.url
    bucket_url_ds    = module.ds-bucket.url
    ds_name_faq      = module.dialogflow.data_stores["faq"].name
    ds_name_kb       = module.dialogflow.data_stores["kb"].name
    ds_uri_faq       = local.uris["ds_faq"]
    ds_uri_kb        = local.uris["ds_kb"]
    project_id       = var.project_config.id
    service_accounts = var.service_accounts
    webhooks         = local.webhooks
  })
}
