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
  effective_user_identity = coalesce(
    try(data.google_client_openid_userinfo.me[0].email, null),
    "tests@automation.com"
  )
}

module "projects" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project-factory?ref=v57.0.0"
  data_defaults = {
    billing_account = var.project_config.billing_account_id
    parent          = var.project_config.parent
    prefix          = var.prefix
    bucket = {
      force_destroy = !var.enable_deletion_protection
    }
    locations = {
      storage = var.region
    }
  }
  factories_config = {
    basepath = "./data"
    exclusions = {
      projects = var.networking_config.create ? [] : ["host"]
    }
    paths = {
      projects = "projects"
    }
  }
  context = {
    condition_vars = {
      networking_config = {
        host_project_id = var.networking_config.host_project_id
        region          = var.region
        subnet_name     = var.networking_config.subnet.name
      }
    }
  }
}

data "google_client_openid_userinfo" "me" {
  count = var.enable_iac_sa_impersonation ? 1 : 0
}

resource "google_service_account_iam_member" "me_sa_token_creator" {
  count              = var.enable_iac_sa_impersonation ? 1 : 0
  service_account_id = module.projects.service_accounts["service-01/iac-rw"].id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${local.effective_user_identity}"
}
