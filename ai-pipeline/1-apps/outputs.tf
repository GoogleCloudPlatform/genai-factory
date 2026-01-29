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
  gcloud storage cp data/top-100-imdb-movies.csv gs://${var.project_config.id}-pipeline-artifacts/data/

  # Create a python virtual environment
  python3 -m venv venv
  source venv/bin/activate
  pip install --upgrade google-cloud-aiplatform

  # Launch the Vertex AI custom job:
  python3 apps/pipeline_psc.py \
    --project ${var.project_config.id} \
    --region ${var.region} \
    --bucket gs://${var.project_config.id}-pipeline-artifacts  \
    --service_account ${var.service_accounts["project/gf-pipeline-0"].email} \
    --network_attachment ${google_compute_network_attachment.network_attachment[0].name} \
    --target_network ${module.vpc[0].name} \
    --db_host ${google_dns_record_set.cloudsql_dns_record_set.name} \
    --db_user ${var.service_accounts["project/gf-pipeline-0"].email} \
    --proxy_url ${local.proxy_ip} \
    --proxy_port ${var.networking_config.proxy_port} \
    --dns_domains "sql.goog." \
    --input_file gs://${var.project_config.id}-pipeline-artifacts/data/top-100-imdb-movies.csv
    EOT
}
