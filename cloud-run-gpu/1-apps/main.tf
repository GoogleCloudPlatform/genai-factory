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

module "cloud_run" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2?ref=daily-2025.08.19"
  project_id = var.project_config.id
  name       = var.name
  region     = var.region
  service_config = {
    gen2_execution_environment = true
    ingress                    = var.cloud_run_configs.ingress
  }
  containers          = var.cloud_run_configs.containers
  service_account     = var.service_accounts["project/gf-rgpu-0"].email
  deletion_protection = var.enable_deletion_protection
  managed_revision    = false
  iam = {
    "roles/run.invoker" = var.cloud_run_configs.service_invokers
  }
  revision = {
    gen2_execution_environment    = true
    max_instance_count            = var.cloud_run_configs.max_instance_count,
    gpu_zonal_redundancy_disabled = var.cloud_run_configs.gpu_zonal_redundancy_disabled
    node_selector                 = var.cloud_run_configs.node_selector
  }
}