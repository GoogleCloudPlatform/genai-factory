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

# tfdoc:file:description Location-level Discovery Engine singletons (ACL, CMEK, and user store).

resource "google_discovery_engine_acl_config" "default" {
  count    = var.gemini_enterprise_iam.idp_type != null ? 1 : 0
  project  = var.project_id
  location = var.location

  idp_config {
    idp_type = var.gemini_enterprise_iam.idp_type

    dynamic "external_idp_config" {
      for_each = var.gemini_enterprise_iam.idp_type == "THIRD_PARTY" ? [""] : []

      content {
        workforce_pool_name = var.gemini_enterprise_iam.workforce_pool_name
      }
    }
  }
}

resource "google_discovery_engine_cmek_config" "default" {
  count           = var.gemini_enterprise_encryption_config == null ? 0 : 1
  project         = var.project_id
  location        = var.location
  cmek_config_id  = var.gemini_enterprise_encryption_config.cmek_config_id
  deletion_policy = local.deletion_policy
  kms_key         = var.gemini_enterprise_encryption_config.kms_key
  set_default     = var.gemini_enterprise_encryption_config.set_default

  dynamic "single_region_keys" {
    for_each = var.gemini_enterprise_encryption_config.single_region_keys

    content {
      kms_key = single_region_keys.value
    }
  }

  lifecycle {
    precondition {
      condition     = contains(["us", "eu"], var.location)
      error_message = "gemini_enterprise_encryption_config (google_discovery_engine_cmek_config) is only supported when location is 'us' or 'eu'."
    }
  }
}

resource "google_discovery_engine_user_store" "default" {
  count                              = var.gemini_enterprise_user_store_config == null ? 0 : 1
  project                            = var.project_id
  location                           = var.location
  user_store_id                      = "default_user_store"
  default_license_config             = var.gemini_enterprise_user_store_config.default_license_config
  enable_expired_license_auto_update = var.gemini_enterprise_user_store_config.enable_expired_license_auto_update
  enable_license_auto_register       = var.gemini_enterprise_user_store_config.enable_license_auto_register
}
