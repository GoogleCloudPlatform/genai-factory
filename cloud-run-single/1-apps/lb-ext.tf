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

# Cloud Armor security policy
resource "google_compute_security_policy" "security_policy_external" {
  count   = var.lbs_config.external.enable ? 1 : 0
  name    = "${var.name}-external"
  project = var.project_config.id

  dynamic "rule" {
    for_each = (
      try(length(var.lbs_config.external.allowed_ip_ranges), 0) > 0 ? [""] : []
    )

    content {
      action      = "allow"
      priority    = "100"
      description = "Allowed source IP ranges."

      match {
        versioned_expr = "SRC_IPS_V1"

        config {
          src_ip_ranges = var.lbs_config.external.allowed_ip_ranges
        }
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = "2147483647"
    description = "Default deny rule."

    match {
      versioned_expr = "SRC_IPS_V1"

      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

resource "google_compute_global_address" "address_external" {
  count = (
    var.lbs_config.external.enable &&
    var.lbs_config.external.ip_address == null
    ? 1 : 0
  )
  project    = var.project_config.id
  name       = "${var.name}-external"
  ip_version = "IPV4"
}

module "lb_external_redirect" {
  count               = var.lbs_config.external.enable ? 1 : 0
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-ext"
  project_id          = var.project_config.id
  name                = "${var.name}-external-redirect"
  use_classic_version = false
  forwarding_rules_config = {
    "" = {
      address = coalesce(
        var.lbs_config.external.ip_address,
        google_compute_global_address.address_external[0].address
      )
    }
  }
  health_check_configs = {}
  urlmap_config = {
    description = "HTTP to HTTPS redirect."
    default_url_redirect = {
      https         = true
      response_code = "MOVED_PERMANENTLY_DEFAULT"
    }
  }
}

module "lb_external" {
  count               = var.lbs_config.external.enable ? 1 : 0
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-ext"
  project_id          = var.project_config.id
  name                = "${var.name}-external"
  use_classic_version = false
  protocol            = "HTTPS"
  forwarding_rules_config = {
    "" = {
      address = coalesce(
        var.lbs_config.external.ip_address,
        google_compute_global_address.address_external[0].address
      )
    }
  }
  backend_service_configs = {
    default = {
      port_name = ""
      backends = [
        { backend = "${var.name}-external" }
      ]
      health_checks   = []
      security_policy = google_compute_security_policy.security_policy_external[0].id
    }
  }
  health_check_configs = {}
  neg_configs = {
    ("${var.name}-external") = {
      cloudrun = {
        region = var.region
        target_service = {
          name = module.cloud_run.service_name
        }
      }
    }
  }
  ssl_certificates = {
    managed_configs = {
      default = {
        domains = [var.lbs_config.external.domain]
      }
    }
  }
}
