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
  iam_principals = {
    for k, v in var.service_accounts
    : k => v.email
  }
}

module "cloud_run" {
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2?ref=v55.1.0"
  type                = "SERVICE"
  project_id          = var.project_id
  name                = var.name
  region              = var.region
  containers          = var.cloud_run_config.containers
  deletion_protection = var.enable_deletion_protection
  managed_revision    = false
  service_account_config = {
    create = false
    email  = var.service_account_emails["service-01/crun-0"]
  }
  iam = {
    "roles/run.invoker" = var.cloud_run_config.service_invokers
  }
  revision = {
    gpu_zonal_redundancy_disabled = var.cloud_run_config.gpu_zonal_redundancy_disabled
    node_selector                 = var.cloud_run_config.node_selector
    vpc_access = {
      egress  = var.cloud_run_config.vpc_access_egress
      network = var.networking_config.vpc
      subnet  = var.networking_config.subnet
      tags    = var.cloud_run_config.vpc_access_tags
    }
  }
  service_config = {
    gen2_execution_environment = true
    ingress                    = var.cloud_run_config.ingress
    scaling = {
      max_instance_count = var.cloud_run_config.max_instance_count
      min_instance_count = var.cloud_run_config.min_instance_count
    }
  }
  context = {
    iam_principals = local.iam_principals
    networks       = var.vpc_self_links
    subnets        = var.subnet_self_links
  }
}
