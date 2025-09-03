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
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2?ref=v42.1.0"
  type                = "SERVICE"
  project_id          = var.project_config.id
  name                = var.name
  region              = var.region
  containers          = var.cloud_run_configs.containers
  service_account     = var.service_accounts["project/gf-srun-0"].email
  deletion_protection = var.enable_deletion_protection
  managed_revision    = false
  iam = {
    "roles/run.invoker" = var.cloud_run_configs.service_invokers
  }
  revision = {
    vpc_access = {
      egress  = var.cloud_run_configs.vpc_access_egress
      network = local.vpc_id
      subnet  = local.subnet_id
      tags    = var.cloud_run_configs.vpc_access_tags
    }
  }
  service_config = {
    gen2_execution_environment = true
    ingress                    = var.cloud_run_configs.ingress
    max_instance_count         = var.cloud_run_configs.max_instance_count
  }
}
