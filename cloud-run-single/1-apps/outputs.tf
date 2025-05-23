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

output "commands" {
  description = "Run the following commands when the deployment completes to deploy the app."
  value       = <<EOT
  # Run the following commands to deploy the application.
  # Alternatively, deploy the application through your CI/CD pipeline.

  gcloud run deploy ${var.name} \
    --source ./apps/chat \
    --set-env-vars PROJECT_ID=${var.project_config.id} \
    --set-env-vars REGION=${var.region} \
    --project ${var.project_config.id} \
    --region ${var.region} \
    --build-service-account ${var.service_accounts["project/gf-srun-build-0"].id} \
    --quiet
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
