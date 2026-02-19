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

data "google_client_openid_userinfo" "me" {
  count = var.enable_iac_sa_impersonation ? 1 : 0
}

resource "google_service_account_iam_member" "me_sa_token_creator" {
  count              = var.enable_iac_sa_impersonation ? 1 : 0
  service_account_id = module.projects.service_accounts["service/iac-rw"].id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${local.effective_user_identity}"
}
