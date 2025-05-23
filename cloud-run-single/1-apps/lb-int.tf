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
resource "google_compute_region_security_policy" "security_policy_internal" {
  count   = var.lbs_config.internal.enable ? 1 : 0
  name    = "${var.name}-internal"
  project = var.project_config.id
  region  = var.region
  type    = "CLOUD_ARMOR"

  dynamic "rules" {
    for_each = (
      try(length(var.lbs_config.internal.allowed_ip_ranges), 0) > 0 ? [""] : []
    )

    content {
      action      = "allow"
      priority    = "100"
      description = "Allowed source IP ranges."

      match {
        versioned_expr = "SRC_IPS_V1"

        config {
          src_ip_ranges = var.lbs_config.internal.allowed_ip_ranges
        }
      }
    }
  }

  rules {
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

resource "google_compute_address" "address_internal" {
  count        = var.lbs_config.internal.enable ? 1 : 0
  name         = "${var.name}-internal"
  project      = var.project_config.id
  address_type = "INTERNAL"
  purpose      = "SHARED_LOADBALANCER_VIP"
  subnetwork   = local.subnet_id
  region       = var.region
}

module "lb_internal_redirect" {
  count                = var.lbs_config.internal.enable ? 1 : 0
  source               = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-int"
  name                 = "${var.name}-internal-redirect"
  project_id           = var.project_config.id
  region               = var.region
  health_check_configs = {}
  address = coalesce(
    var.lbs_config.internal.ip_address,
    google_compute_address.address_internal[0].address
  )
  urlmap_config = {
    description = "HTTP to HTTPS redirect."
    default_url_redirect = {
      https         = true
      response_code = "MOVED_PERMANENTLY_DEFAULT"
      strip_query   = false
    }
  }
  vpc_config = {
    network    = local.vpc_id
    subnetwork = local.subnet_id
  }
}

module "lb_internal" {
  count                = var.lbs_config.internal.enable ? 1 : 0
  source               = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-int"
  name                 = "${var.name}-internal"
  project_id           = var.project_config.id
  region               = var.region
  protocol             = "HTTPS"
  health_check_configs = {}
  address = coalesce(
    var.lbs_config.internal.ip_address,
    google_compute_address.address_internal[0].address
  )
  backend_service_configs = {
    default = {
      port_name = ""
      backends = [
        { group = "${var.name}-internal" }
      ]
      health_checks   = []
      security_policy = google_compute_region_security_policy.security_policy_internal[0].id
    }
  }
  neg_configs = {
    ("${var.name}-internal") = {
      cloudrun = {
        region = var.region
        target_service = {
          name = module.cloud_run.service_name
        }
      }
    }
  }
  https_proxy_config = {
    certificate_manager_certificates = [
      for k, v in module.certificate_manager[0].certificates : v.id
    ]
  }
  vpc_config = {
    network    = local.vpc_id
    subnetwork = local.subnet_id
  }
}

# DNS Zone for internal resolution
module "lb_internal_dns" {
  count      = var.lbs_config.internal.enable ? 1 : 0
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/dns"
  project_id = var.project_config.id
  name       = var.name
  zone_config = {
    domain = "${var.lbs_config.internal.domain}."
    private = {
      client_networks = [local.vpc_id]
    }
  }
  recordsets = {
    ("A ${var.lbs_config.internal.domain}") = {
      records = [module.lb_internal.0.address]
      ttl     = 300
    }
  }
}
