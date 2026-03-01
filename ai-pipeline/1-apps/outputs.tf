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
  gcloud storage cp data/top-100-imdb-movies.csv gs://${var.project_config.id}-${var.name}/data/

  # Create artifact registry repository
  # TODO: Replace in all factories by a variable and create with Terraform if not provided by the user
  gcloud artifacts repositories create ${var.name} \
  --project=${var.project_config.id} \
  --location ${var.region} \
  --repository-format docker \
  --impersonate-service-account=${var.service_accounts["project/iac-rw"].email}
  
  # Build the custom container image using Cloud Build and upload to artifact registry
  gcloud builds submit apps/psc-pipeline \
    --tag ${var.region}-docker.pkg.dev/${var.project_config.id}/${var.name}/psc-pipeline:latest \
    --project ${var.project_config.id} \
    --service-account ${var.service_accounts["project/gf-pipeline-0-build-0"].id} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --region ${var.region} \
    --quiet \
    --impersonate-service-account=${var.service_accounts["project/iac-rw"].email}

  # Get the access token for the REST API
  ACCESS_TOKEN=$(gcloud auth print-access-token --impersonate-service-account=${var.service_accounts["project/iac-rw"].email})
  # Create the Vertex AI custom job via REST API
  curl -X POST "https://${var.region}-aiplatform.googleapis.com/v1/projects/${var.project_config.id}/locations/${var.region}/customJobs" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "displayName": "custom-job-psc",
  "jobSpec": {
    "workerPoolSpecs": [
      {
        "machineSpec": {
          "machineType": "n2-standard-4"
        },
        "replicaCount": 1,
        "containerSpec": {
            "imageUri": "${var.region}-docker.pkg.dev/${var.project_config.id}/${var.name}/psc-pipeline:latest",
            "env": [
              { "name": "PROJECT_ID", "value": "${var.project_config.id}" },
              { "name": "REGION", "value": "${var.region}" },
              { "name": "INPUT_FILE", "value": "gs://${var.project_config.id}-${var.name}/data/top-100-imdb-movies.csv" },
              { "name": "DB_HOST", "value": "${google_dns_record_set.cloudsql_dns_record_set.name}" },
              { "name": "DB_NAME", "value": "cloud-sql-db" },
              { "name": "DB_USER", "value": "${var.service_accounts["project/gf-pipeline-0"].email}" },
              { "name": "PROXY_ADDRESS", "value": "${local.proxy_ip}" },
              { "name": "PROXY_PORT", "value": "${var.networking_config.proxy_port}" }
            ]
        }
      }
    ],
    "serviceAccount": "${var.service_accounts["project/gf-pipeline-0"].email}",
    "pscInterfaceConfig": {
      "networkAttachment": "${local.network_attachment_id}",
      "dnsPeeringConfigs": [
        {
          "domain": "sql.goog.",
          "targetProject": "${var.project_config.id}",
          "targetNetwork": "${module.vpc[0].name}"
        }
      ]
    },
    "enableWebAccess": true
  }
}
EOF
EOT
}
