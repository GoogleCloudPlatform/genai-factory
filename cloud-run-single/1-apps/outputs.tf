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
  _env_vars = [
    "PROJECT_ID=${var.project_config.id}",
    "REGION=${var.region}",
  ]
  env_vars = join(",", local._env_vars)
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

  # Update chat to adk if you want to deploy the adk app instead

  gcloud builds submit ./apps/chat \
    --project ${var.project_config.id} \
    --tag ${var.region}-docker.pkg.dev/${var.project_config.id}/${var.name}/srun \
    --service-account ${var.service_accounts["project/gf-srun-build-0"].id} \
    --default-buckets-behavior=REGIONAL_USER_OWNED_BUCKET \
    --quiet \
    --impersonate-service-account=${var.service_accounts["project/iac-rw"].email}

  gcloud run deploy ${var.name} \
    --impersonate-service-account=${var.service_accounts["project/iac-rw"].email} \
    --project ${var.project_config.id} \
    --region ${var.region} \
    --image=${var.region}-docker.pkg.dev/${var.project_config.id}/${var.name}/srun \
    --set-env-vars ${local.env_vars}
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
