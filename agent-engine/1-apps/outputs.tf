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

output "commands" {
  description = "Run the following commands when the deployment finalize the setup, deploy and test your agent."
  value       = <<EOT
  # Store Google access token for iac-rw SA

  ACCESS_TOKEN=$(gcloud auth print-access-token --impersonate-service-account=${var.service_accounts["project/iac-rw"].email})

  # Setup PSC-I
  # (thus allowing private communication of your agent with your VPC).

  curl -X PATCH "https://${var.region}-aiplatform.googleapis.com/v1/${module.agent.id}" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "networkSpec": {
        "private_service_connect_config": {
          "enable_private_service_connect": true,
          "project_allowlist": [
            "${var.project_config.number}"
          ]
        }
      }
    }'

  # Run the following commands to deploy the application.
  # Alternatively, deploy the application through your CI/CD pipeline.

  tar czf source.tar.gz apps/adk-a2a &&

  TAR_GZ_BASE64=$(openssl base64 -in source.tar.gz | tr -d '\n')

  curl -X PATCH "https://${var.region}-aiplatform.googleapis.com/v1/${module.agent.id}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "spec": {
    "sourceCodeSpec": {
      "pythonSpec": {
        "entrypointModule": "agent",
        "entrypointObject": "agent",
        "requirementsFile": "requirements.txt",
        "version": "3.12"
      },
      "inlineSource": {
        "sourceArchive": "$TAR_GZ_BASE64"
      }
    }
  }
}
EOF

  # Test the agent.

  curl -X POST https://${var.region}-aiplatform.googleapis.com/v1/${module.agent.id}:streamQuery \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{ "input": { "message": "Hello!", "user_id": "user_123" } }'
  EOT
}
