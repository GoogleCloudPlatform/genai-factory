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

module "cloud_function" {
  count       = var.cloud_function_config.create ? 1 : 0
  source      = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-function-v2?ref=v54.1.0"
  project_id  = var.project_config.id
  region      = var.region
  name        = var.name
  bucket_name = module.gcs_bucket.name
  bundle_config = {
    path = var.cloud_function_config.bundle_path
  }
  direct_vpc_egress = {
    network    = local.vpc_id
    subnetwork = local.subnet_id
    tags       = var.cloud_function_config.direct_vpc_egress_tags
    mode       = var.cloud_function_config.direct_vpc_egress_mode
  }
  service_account_config = {
    create = false
    email  = var.service_accounts["project/gecx-df-0"].email
  }
  build_service_account = var.service_accounts["project/gecx-df-0"].email
  iam = {
    "roles/run.invoker" = concat(
      var.cloud_function_config.service_invokers,
      # This allows Dialogflow CX (through its service agent) to call the function
      ["serviceAccount:service-agent-project-${var.project_config.number}@gcp-sa-dialogflow.iam.gserviceaccount.com"]
    )
  }
}

module "gcs_bucket" {
  source                   = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v54.1.0"
  project_id               = var.project_config.id
  prefix                   = var.project_config.prefix
  name                     = var.name
  location                 = var.region
  versioning               = true
  public_access_prevention = "enforced"
}
