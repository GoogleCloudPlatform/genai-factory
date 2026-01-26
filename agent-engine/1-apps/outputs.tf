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

output "agent_id" {
  description = "The agent engine agent id."
  value       = module.agent.id
}

output "commands" {
  description = "Run the following commands when the deployment finalize the setup, deploy and test your agent."
  value       = <<EOT
  # Generate access token for authentication

  ACCESS_TOKEN=$(gcloud auth print-access-token --impersonate-service-account=${var.service_accounts["project/iac-rw"].email})

  # Optionally, setup PSC-I (can't be done via Terraform, yet)

  curl -X PATCH "https://${var.region}-aiplatform.googleapis.com/v1/${module.agent.id}?updateMask=spec.deploymentSpec.pscInterfaceConfig" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
      {
        "spec": {
          "deploymentSpec": {
            "pscInterfaceConfig": {
              "networkAttachment": "${local.network_attachment_id}",
              "dnsPeeringConfigs": [
                {
                  "domain": ".",
                  "targetProject": "${var.project_config.id}",
                  "targetNetwork": "${local.vpc_name}"
                }
              ]
            }
          }
        }
      }
EOF

  # Run these commands to deploy the application.
  # Substitute the app folder and other options as needed.
  # Alternatively, deploy the application through your CI/CD pipeline.

  cd apps/adk && tar -czf ${var.source_config.tar_gz_file_name} * &&
  cd ../../ && mv apps/adk/${var.source_config.tar_gz_file_name} . &&
  TAR_GZ_BASE64=$(openssl base64 -in ${var.source_config.tar_gz_file_name}) &&
  curl -X PATCH "https://${var.region}-aiplatform.googleapis.com/v1/${module.agent.id}?updateMask=spec.sourceCodeSpec" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
      {
        "spec": {
          "sourceCodeSpec": {
            "pythonSpec": {
              "entrypointModule": "${var.source_config.entrypoint_module}",
              "entrypointObject": "${var.source_config.entrypoint_object}",
              "requirementsFile": "${var.source_config.requirements_path}",
              "version": "${var.agent_engine_config.python_version}"
            },
            "inlineSource": {
              "sourceArchive": "$TAR_GZ_BASE64"
            }
          }
        }
      }
EOF

  # Test the agent.
  # Export these environment variables.
  # Then, refer to the README.md files in the each apps/ folder to test your agent.

  AGENT_ID=${module.agent.id}
  PROJECT_NUMBER=${var.project_config.number}
  REGION=${var.region}
EOT
}
