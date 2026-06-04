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
  # Extract service account emails and ids from var.service_accounts, if any
  _service_account_emails = {
    for k, v in var.service_accounts : k => v.email
  }
  # if the emails provided by the user are keys of var.service_accounts
  # return the corresponding value, otherwise keep the email
  service_account_emails = {
    for k, v in var.service_account_emails
    : k => lookup(local._service_account_emails, v, v)
  }
  toolsets = merge(
    merge([
      for namespace_name, namespace_config in var.service_directory_configs : {
        for service_name, service_config in namespace_config.services :
        "${service_name}-${namespace_name}" => {
          allowed_ca_certs  = service_config.allowed_ca_certs
          openapi_spec      = service_config.openapi_spec
          service_directory = module.service_directory[namespace_name].service_id[service_name]
          uri               = "${module.service_directory[namespace_name].services[service_name].service_id}.${namespace_config.cloud_dns_domain}"
        }
      }
    ]...),
    {
      "function-example-com" = {
        allowed_ca_certs  = [filebase64("data/function-cert/cert.der")]
        openapi_spec      = "data/function/openapi-spec.yaml"
        service_directory = module.service_directory["example-com"].service_id["function"]
        uri               = "${module.service_directory["example-com"].services["function"].service_id}.${var.cloud_function_config.cert_common_name}"
      }
    }
  )
}

output "commands" {
  description = "Run these commands to complete the deployment."
  value = templatefile("./templates/outputs.sh", {
    app_id                  = google_ces_app.gecx_as_app.app_id
    bucket_url_build        = module.build-bucket.url
    bucket_url_ds           = module.ds-bucket.url
    ds_name                 = google_discovery_engine_data_store.knowledge_base.name
    project_id              = var.project_id
    region_discovery_engine = var.region_discovery_engine
    service_account_emails  = local.service_account_emails
    toolsets                = local.toolsets
  })
}
