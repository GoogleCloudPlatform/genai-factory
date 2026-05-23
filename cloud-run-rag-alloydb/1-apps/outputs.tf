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
  _sa_db_frontend = trimsuffix(
    var.service_account_emails["service-01/gf-rrag-fe-0"],
    ".gserviceaccount.com"
  )
  _sa_db_ingestion = trimsuffix(
    var.service_account_emails["service-01/gf-rrag-ing-0"],
    ".gserviceaccount.com"
  )

  _env_vars_frontend = [
    "DB_NAME=${var.name}",
    "DB_SA=${local._sa_db_frontend}",
    "DB_TABLE=${var.name}",
    "PROJECT_ID=${var.project_id}",
    "REGION=${var.region}"
  ]
  _env_vars_ingestion = [
    "BQ_DATASET=${local.bigquery_id}",
    "BQ_TABLE=${local.bigquery_id}",
    "DB_NAME=${var.name}",
    "DB_SA=${local._sa_db_ingestion}",
    "DB_TABLE=${var.name}",
    "PROJECT_ID=${var.project_id}",
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

  # Set the postgres user password
  gcloud alloydb users set-password postgres \
  --cluster alloydb \
  --password YOUR_COMPLEX_PASSWORD_HERE \
  --project ${var.project_id} \
  --region ${var.region}

  # Install the vector extension in AlloyDB
  -> # In https://console.cloud.google.com/alloydb/locations/${var.region}/clusters/alloydb/studio
     # Select the ${var.name} database and enter with postgres user.
     # In the Editor 1 tab, run this query: CREATE EXTENSION IF NOT EXISTS vector;
     # This requires the user to be AlloyDB admin.
     # Then, create the database: CREATE DATABASE "${var.name}";

  # Load sample data into BigQuery
  gcloud config set auth/impersonate_service_account ${var.service_account_emails["service-01/iac-rw"]}
  bq load \
    --project_id ${var.project_id} \
    --source_format=CSV \
    --skip_leading_rows=1 \
    --autodetect \
    ${var.project_id}:${local.bigquery_id}.${local.bigquery_id} \
    ./data/top-100-imdb-movies.csv
  gcloud config unset auth/impersonate_service_account

  gcloud artifacts repositories create ${var.name} \
    --project=${var.project_id} \
    --location ${var.region} \
    --repository-format docker \
    --impersonate-service-account=${var.service_account_emails["service-01/iac-rw"]}

  # Ingestion Cloud Run
  gcloud builds submit ./apps/rag/ingestion \
    --project ${var.project_id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_id}/${var.name}/ingestion \
    --service-account ${var.service_account_ids["service-01/gf-rrag-ing-build-0"]} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --region ${var.region} \
    --quiet \
    --impersonate-service-account=${var.service_account_emails["service-01/iac-rw"]}

  gcloud run jobs deploy ${var.name}-ingestion \
    --impersonate-service-account=${var.service_account_emails["service-01/iac-rw"]} \
    --project ${var.project_id} \
    --region ${var.region} \
    --container=ingestion \
    --image=${var.region}-docker.pkg.dev/${var.project_id}/${var.name}/ingestion \
    --set-env-vars ${local.env_vars_ingestion}

  # Frontend Cloud Run
  gcloud builds submit ./apps/rag/frontend \
    --project ${var.project_id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_id}/${var.name}/frontend \
    --service-account ${var.service_account_ids["service-01/gf-rrag-fe-build-0"]} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --region ${var.region} \
    --quiet \
    --impersonate-service-account=${var.service_account_emails["service-01/iac-rw"]}

  gcloud run deploy ${var.name}-frontend \
    --impersonate-service-account=${var.service_account_emails["service-01/iac-rw"]} \
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
      ? module.lb_ext_glb[0].address
      : null
    )
    internal = (
      var.lbs_configs.internal.enable
      ? module.lb_internal[0].address
      : null
    )
  }
}
