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
    "DB_NAME=${var.name}",
    "DB_SA=${var.service_accounts["project/gf-rrag-fe-0"].id}",
    "DB_TABLE=${var.name}",
    "PROJECT_ID=${var.project_config.id}",
    "REGION=${var.region}"
  ]
  _env_vars_ingestion = [
    "BQ_DATASET=${local.bigquery_id}",
    "BQ_TABLE=${local.bigquery_id}",
    "DB_NAME=${var.name}",
    "DB_SA=${var.service_accounts["project/gf-rrag-ing-0"].id}@${var.project_config.id}.iam",
    "DB_TABLE=${var.name}",
    "PROJECT_ID=${var.project_config.id}",
    "REGION=${var.region}"
  ]
  env_vars_frontend  = join(",", local._env_vars_frontend)
  env_vars_ingestion = join(",", local._env_vars_ingestion)
}

output "commands" {
  description = "Run the following commands when the deployment completes to deploy the app."
  value       = <<EOT
  # Run the following commands to deploy the application.
  # Alternatively, deploy the application through your CI/CD pipeline.

  # Install the vector extension in CloudSQL
  # There's no way to activate extensions in CloudSQL from Terraform.
  # - Go to https://console.cloud.google.com/sql/instances/${var.name}/users.
  # - Give a secure password to your postgres user
  # - In https://console.cloud.google.com/sql/instances/${var.name}/studio select any database and enter with postgres user.
  # - Run this query: CREATE EXTENSION IF NOT EXISTS vector;

  # Load sample data into BigQuery
  bq load \
    --source_format=CSV \
    --skip_leading_rows=1 \
    --autodetect \
    ${var.project_config.id}:${local.bigquery_id}.${local.bigquery_id} \
    ./data/top-100-imdb-movies.csv

  gcloud artifacts repositories create ${var.name} \
    --project=${var.project_config.id} \
    --location ${var.region} \
    --repository-format docker

  # Ingestion Cloud Run
  gcloud builds submit ./apps/rag/ingestion \
    --project ${var.project_config.id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_config.id}/cloud-run-source-deploy/ingestion \
    --service-account ${var.service_accounts["project/gf-rrag-ing-build-0"].id} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --quiet

  gcloud run jobs deploy ${var.name}-ingestion \
    --project ${var.project_config.id} \
    --region ${var.region} \
    --container=ingestion \
    --image=${var.region}-docker.pkg.dev/${var.project_config.id}/cloud-run-source-deploy/ingestion \
    --set-env-vars ${local.env_vars_ingestion}

  # Frontend Cloud Run
  gcloud builds submit ./apps/rag/frontend \
    --project ${var.project_config.id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_config.id}/cloud-run-source-deploy/frontend \
    --service-account ${var.service_accounts["project/gf-rrag-fe-build-0"].id} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --quiet

  gcloud run jobs deploy ${var.name}-frontend \
    --project ${var.project_config.id} \
    --region ${var.region} \
    --container=frontend \
    --image=${var.region}-docker.pkg.dev/${var.project_config.id}/cloud-run-source-deploy/frontend \
    --set-env-vars ${local.env_vars_frontend}
  EOT
}

output "ip_addresses" {
  description = "The load balancers IP addresses."
  value = {
    external = (
      var.lbs_config.external.enable
      ? module.lb_external[0].address
      : null
    )
    internal = (
      var.lbs_config.internal.enable
      ? module.lb_internal[0].address
      : null
    )
  }
}
