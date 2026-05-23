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
  _env_vars_frontend = [
    "GCS_SOURCE_BUCKET=${module.index-bucket.name}",
    "PROJECT_ID=${var.project_id}",
    "REGION=${var.region}",
    "VECTOR_SEARCH_INDEX_ENDPOINT_NAME=${google_vertex_ai_index_endpoint.index_endpoint.name}",
    "VECTOR_SEARCH_DEPLOYED_INDEX_ID=${google_vertex_ai_index_endpoint_deployed_index.index_deployment.deployed_index_id}",
    "VECTOR_SEARCH_ENDPOINT_IP_ADDRESS=${google_compute_address.vector_search_address.address}"
  ]
  _env_vars_ingestion = [
    "GCS_SOURCE_BUCKET=${module.index-bucket.name}",
    "PROJECT_ID=${var.project_id}",
    "REGION=${var.region}",
    "VECTOR_SEARCH_INDEX_NAME=${google_vertex_ai_index.index.id}"
  ]
  # Extract service account emails and ids from var.service_accounts, if any
  _service_account_emails = {
    for k, v in var.service_accounts : k => v.email
  }
  _service_account_ids = {
    for k, v in var.service_accounts : k => v.id
  }
  env_vars_frontend  = join(",", local._env_vars_frontend)
  env_vars_ingestion = join(",", local._env_vars_ingestion)
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

  # Ingestion Cloud Run
  gcloud builds submit ./apps/rag/ingestion \
    --project ${var.project_id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_id}/${var.name}/ingestion \
    --service-account ${local.service_account_ids["service-01/gf-rrag-ing-build-0"]} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --region ${var.region} \
    --quiet \
    --impersonate-service-account=${local.service_account_emails["service-01/iac-rw"]}

  gcloud run jobs deploy ${var.name}-ingestion \
    --impersonate-service-account=${local.service_account_emails["service-01/iac-rw"]} \
    --project ${var.project_id} \
    --region ${var.region} \
    --container=ingestion \
    --image=${var.region}-docker.pkg.dev/${var.project_id}/${var.name}/ingestion \
    --set-env-vars ${local.env_vars_ingestion}

  # Frontend Cloud Run
  gcloud builds submit ./apps/rag/frontend \
    --project ${var.project_id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_id}/${var.name}/frontend \
    --service-account ${local.service_account_ids["service-01/gf-rrag-fe-build-0"]} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --region ${var.region} \
    --quiet \
    --impersonate-service-account=${local.service_account_emails["service-01/iac-rw"]}

  gcloud run deploy ${var.name}-frontend \
    --impersonate-service-account=${local.service_account_emails["service-01/iac-rw"]} \
    --project ${var.project_id} \
    --region ${var.region} \
    --container=frontend \
    --image=${var.region}-docker.pkg.dev/${var.project_id}/${var.name}/frontend \
    --set-env-vars ${local.env_vars_frontend}
  EOT
}

output "ip_addresses" {
  description = "The load balancers IP addresses."
  value = {
    external = (
      var.lbs_configs.external.enable
      ? module.lb_external[0].address[""]
      : null
    )
    internal = (
      var.lbs_configs.internal.enable
      ? module.lb_internal[0].address
      : null
    )
  }
}
