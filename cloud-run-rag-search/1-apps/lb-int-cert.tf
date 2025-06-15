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

module "cas" {
  count      = var.lbs_config.internal.enable ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-authority-service"
  project_id = var.project_config.id
  location   = var.region
  ca_pool_config = {
    create_pool = {
      tier = "DEVOPS"
      name = "${var.name}-${var.ca_pool_name_suffix}"
    }
  }
  ca_configs = {
    (var.name) = {
      deletion_protection                    = var.enable_deletion_protection
      skip_grace_period                      = true
      ignore_active_certificates_on_deletion = !var.enable_deletion_protection
      key_spec_algorithm                     = "RSA_PKCS1_4096_SHA256"
      subject = {
        common_name  = var.lbs_config.internal.domain
        organization = var.name
      }
      key_usage = {
        certSign         = true
        crlSign          = true
        key_encipherment = false
        server_auth      = false
      }
    }
  }
}
