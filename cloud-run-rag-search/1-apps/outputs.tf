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
  _env_vars_frontend = [
    "GCS_SOURCE_BUCKET=${module.index-bucket.name}",
    "PROJECT_ID=${var.project_config.id}",
    "REGION=${var.region}",
    "VECTOR_SEARCH_INDEX_ENDPOINT_NAME=${google_vertex_ai_index_endpoint.index_endpoint.name}",
    "VECTOR_SEARCH_DEPLOYED_INDEX_ID=${google_vertex_ai_index_endpoint_deployed_index.index_deployment.deployed_index_id}",
    "VECTOR_SEARCH_ENDPOINT_IP_ADDRESS=${google_compute_forwarding_rule.vector_search_psc_endpoint.ip_address}"
  ]
  _env_vars_ingestion = [
    "GCS_SOURCE_BUCKET=${module.index-bucket.name}",
    "PROJECT_ID=${var.project_config.id}",
    "REGION=${var.region}",
    "VECTOR_SEARCH_INDEX_NAME=${google_vertex_ai_index.index.id}"
  ]
  env_vars_frontend  = join(",", local._env_vars_frontend)
  env_vars_ingestion = join(",", local._env_vars_ingestion)
}

output "commands" {
  description = "Run the following commands when the deployment completes to deploy the app."
  value       = <<EOT
  # Run the following commands to deploy the application.
  # Alternatively, deploy the application through your CI/CD pipeline.

  gcloud artifacts repositories create ${var.name} \
    --project=${var.project_config.id} \
    --location ${var.region} \
    --repository-format docker \
    --impersonate-service-account=${var.service_accounts["project/iac-rw"].email}

  # Ingestion Cloud Run
  gcloud builds submit ./apps/rag/ingestion \
    --project ${var.project_config.id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_config.id}/${var.name}/ingestion \
    --service-account ${var.service_accounts["project/gf-rrag-ing-build-0"].id} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --quiet \
    --impersonate-service-account=${var.service_accounts["project/iac-rw"].email}

  gcloud run jobs deploy ${var.name}-ingestion \
    --impersonate-service-account=${var.service_accounts["project/iac-rw"].email} \
    --project ${var.project_config.id} \
    --region ${var.region} \
    --container=ingestion \
    --image=${var.region}-docker.pkg.dev/${var.project_config.id}/${var.name}/ingestion \
    --set-env-vars ${local.env_vars_ingestion}

  # Frontend Cloud Run
  gcloud builds submit ./apps/rag/frontend \
    --project ${var.project_config.id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_config.id}/${var.name}/frontend \
    --service-account ${var.service_accounts["project/gf-rrag-fe-build-0"].id} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --quiet \
    --impersonate-service-account=${var.service_accounts["project/iac-rw"].email}

  gcloud run deploy ${var.name}-frontend \
    --impersonate-service-account=${var.service_accounts["project/iac-rw"].email} \
    --project ${var.project_config.id} \
    --region ${var.region} \
    --container=frontend \
    --image=${var.region}-docker.pkg.dev/${var.project_config.id}/${var.name}/frontend \
    --set-env-vars ${local.env_vars_frontend}
  EOT
}

output "ip_addresses" {
  description = "The load balancers IP addresses."
  value = {
    external = (
      var.lbs_config.external.enable
      ? module.lb_external[0].address[""]
      : null
    )
    internal = (
      var.lbs_config.internal.enable
      ? module.lb_internal[0].address
      : null
    )
  }
}
