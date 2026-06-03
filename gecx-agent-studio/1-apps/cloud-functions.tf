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

module "cloud-function" {
  source           = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-function-v2?ref=v56.1.0"
  project_id       = var.project_id
  region           = var.region
  name             = var.name
  bucket_name      = module.gcs_bucket.name
  ingress_settings = "ALLOW_INTERNAL_ONLY"
  # ingress_settings = "ALLOW_INTERNAL_AND_GCLB"
  bundle_config = {
    path = var.cloud_function_config.bundle_path
  }
  direct_vpc_egress = {
    network    = var.networking_config.vpc
    subnetwork = var.networking_config.subnet
    tags       = var.cloud_function_config.direct_vpc_egress_tags
    mode       = var.cloud_function_config.direct_vpc_egress_mode
  }
  service_account_config = {
    create = false
    email  = var.service_account_emails["service-01/gecx-as-0"]
  }
  build_service_account = var.service_account_ids["service-01/gecx-as-0"]
  iam = {
    "roles/run.invoker" = concat(
      var.cloud_function_config.service_invokers,
      # Allows CES (through its service agent) to call the function
      ["serviceAccount:service-${var.number}@gcp-sa-ces.iam.gserviceaccount.com"]
    )
  }
  context = {
    iam_principals = local.iam_principals
    networks       = var.vpc_self_links
    subnets        = var.subnet_self_links
  }
}

module "gcs_bucket" {
  source                   = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v56.1.0"
  project_id               = var.project_id
  prefix                   = var.prefix
  name                     = local.bucket_name
  location                 = var.region
  versioning               = true
  public_access_prevention = "enforced"
  force_destroy            = !var.enable_deletion_protection
}
