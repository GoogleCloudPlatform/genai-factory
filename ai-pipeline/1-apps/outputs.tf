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
  _sa_pipeline = replace(
    var.service_accounts["project/gf-pipeline-0"].email,
    ".gserviceaccount.com",
    ""
  )
  _env_vars_frontend = [
    "DB_NAME=${var.name}",
    "DB_TABLE=${var.name}",
    "PROJECT_ID=${var.project_config.id}",
    "REGION=${var.region}"
  ]
  env_vars_frontend = join(",", local._env_vars_frontend)
}

output "commands" {
  description = "Run the following commands when the deployment completes to deploy the app."
  value       = <<EOT
  # Run the following commands to deploy the application.
  # Alternatively, deploy the application through your CI/CD pipeline.

  # Load CSV file to the Cloud Storage Bucket
  gcloud storage cp data/top-100-imdb-movies.csv gs://${random_id.bucket_prefix.hex}-bucket/

  # Load data to Cloud SQL (can only import from Cloud Storage)
  gcloud sql import csv ${var.name} gs://${random_id.bucket_prefix.hex}-bucket/top-100-imdb-movies.csv \
  --database=cloud-sql-db \
  --table=imdb \
  --project=${var.project_config.id} \
  --impersonate-service-account=${var.service_accounts["project/iac-rw"].email}
  EOT
}