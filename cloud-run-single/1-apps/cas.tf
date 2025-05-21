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

resource "google_project_service_identity" "cm_sa" {
  provider = google-beta
  project = var.project_id
  service = "certificatemanager.googleapis.com"
}

module "cas" {
  count      = var.expose_internal == true ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-authority-service"
  project_id = var.project_id
  location   = var.region
  ca_pool_config = {
    create_pool = {
      tier = "DEVOPS"
      id = "${var.customer_name}-ca-pool"
      name = "${var.customer_name}-ca-pool"
    }
  }
  ca_configs = {
    root_ca_0 = {
        subject = {
          common_name  = var.private_root_domain
          organization = var.customer_name
        } 
        key_spec_algorithm = "RSA_PKCS1_4096_SHA256"
        key_usage = {
          certSign = true
          crlSign = true
          key_encipherment = false
          server_auth = false
        }
        // Disable CA deletion related safe checks for easier cleanup.
        deletion_protection                    = false
        skip_grace_period                      = true
        ignore_active_certificates_on_deletion = true
    }
  }
  depends_on=[
    google_project_service_identity.cm_sa
  ]
}