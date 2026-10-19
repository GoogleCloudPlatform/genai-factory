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
  _env_vars = compact([
    "PROJECT_ID=${var.project_id}",
    "REGION=${var.region}",
    "ENDPOINT_ID=${google_vertex_ai_endpoint_with_model_garden_deployment.model_garden.endpoint}",
    "ENDPOINT_IP_ADDRESS=${module.psc_consumer_address.internal_addresses[var.name].address}",
    try(
      "MODEL_ARMOR_TEMPLATE=${google_model_armor_template.model_armor_template[0].name}",
      null
    )
  ])
  # Extract service account emails and ids from var.service_accounts, if any
  _service_account_emails = {
    for k, v in var.service_accounts : k => v.email
  }
  _service_account_ids = {
    for k, v in var.service_accounts : k => v.id
  }
  env_vars = join(",", local._env_vars)
  # if the emails provided by the user are keys of var.service_accounts
  # return the corresponding value, otherwise keep the email
  service_account_emails = {
    for k, v in var.service_account_emails
    : k => lookup(local._service_account_emails, v, v)
  }
  # if the ids provided by the user are keys of var.service_accounts
  # return the corresponding value, otherwise keep the id
  service_account_ids = {
    for k, v in var.service_account_ids
    : k => lookup(local._service_account_ids, v, v)
  }
}

output "commands" {
  description = "Run the following commands when the deployment completes to deploy the app."
  value       = <<EOT
  # Run the following commands to deploy the application.
  # Alternatively, deploy the application through your CI/CD pipeline.

  gcloud artifacts repositories create ${var.name} \
    --project=${var.project_id} \
    --location ${var.region} \
    --repository-format docker \
    --impersonate-service-account=${local.service_account_emails["service-01/iac-rw"]}

  gcloud builds submit ./apps/chat \
    --project ${var.project_id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_id}/${var.name}/mg \
    --service-account ${local.service_account_ids["service-01/crun-build-0"]} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --region ${var.region} \
    --quiet \
    --impersonate-service-account=${local.service_account_emails["service-01/iac-rw"]}

  gcloud run deploy ${var.name} \
    --impersonate-service-account=${local.service_account_emails["service-01/iac-rw"]} \
    --project ${var.project_id} \
    --region ${var.region} \
    --image=${var.region}-docker.pkg.dev/${var.project_id}/${var.name}/mg \
    --set-env-vars ${local.env_vars}

  EOT
}

output "ip_addresses" {
  description = "The load balancers and PSC endpoint IP addresses."
  value = {
    external = (
      var.lbs_configs.external.enable
      ? local.address_ext_glb
      : null
    )
    internal = (
      var.lbs_configs.internal.enable
      ? local.address_ilb
      : null
    )
    model_garden_psc = module.psc_consumer_address.internal_addresses[var.name].address
  }
}

output "model_garden_endpoint" {
  description = "The deployed Vertex AI Model Garden endpoint details."
  value = {
    deployed_model_id  = google_vertex_ai_endpoint_with_model_garden_deployment.model_garden.deployed_model_id
    endpoint_id        = google_vertex_ai_endpoint_with_model_garden_deployment.model_garden.endpoint
    psc_ip_address     = module.psc_consumer_address.internal_addresses[var.name].address
    service_attachment = google_vertex_ai_endpoint_with_model_garden_deployment.model_garden.endpoint_config[0].private_service_connect_config[0].service_attachment
  }
}
