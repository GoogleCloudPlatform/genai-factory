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
  address_ilb = try(coalesce(
    var.lbs_configs.internal.ip_address,
    module.address-ilb[0].internal_addresses["ilb-01"]
  ), null)
}

# Cloud Armor security policy
resource "google_compute_region_security_policy" "security_policy_internal" {
  count   = var.lbs_configs.internal.enable ? 1 : 0
  name    = "${var.name}-internal"
  project = var.project_id
  region  = var.region
  type    = "CLOUD_ARMOR"

  dynamic "rules" {
    for_each = (
      try(length(var.lbs_configs.internal.allowed_ip_ranges), 0) > 0 ? [""] : []
    )

    content {
      action      = "allow"
      priority    = "100"
      description = "Allowed source IP ranges."

      match {
        versioned_expr = "SRC_IPS_V1"

        config {
          src_ip_ranges = var.lbs_configs.internal.allowed_ip_ranges
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

module "address-ilb" {
  count = (
    var.lbs_configs.internal.enable &&
    var.lbs_configs.internal.ip_address == null
    ? 1 : 0
  )
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-address?ref=v55.1.0"
  project_id = var.project_id
  internal_addresses = {
    ilb-01 = {
      purpose    = "SHARED_LOADBALANCER_VIP"
      region     = var.region
      subnetwork = var.networking_config.subnet
    }
  }
  context = {
    subnets = var.subnet_self_links
  }
}

module "lb_internal_redirect" {
  count                = var.lbs_configs.internal.enable ? 1 : 0
  source               = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-int?ref=v55.1.0"
  name                 = "${var.name}-internal-redirect"
  project_id           = var.project_id
  region               = var.region
  health_check_configs = {}
  address              = local.address_ilb
  urlmap_config = {
    description = "HTTP to HTTPS redirect."
    default_url_redirect = {
      https         = true
      response_code = "MOVED_PERMANENTLY_DEFAULT"
      strip_query   = false
    }
  }
  vpc_config = {
    network    = var.networking_config.vpc
    subnetwork = var.networking_config.subnet
  }
  context = {
    networks = var.vpc_self_links
    subnets  = var.subnet_self_links
  }
}

module "lb_internal" {
  count                = var.lbs_configs.internal.enable ? 1 : 0
  source               = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-int?ref=v55.1.0"
  name                 = "${var.name}-internal"
  project_id           = var.project_id
  region               = var.region
  protocol             = "HTTPS"
  health_check_configs = {}
  address              = local.address_ilb
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
    network    = var.networking_config.vpc
    subnetwork = var.networking_config.subnet
  }
  context = {
    networks = var.vpc_self_links
    subnets  = var.subnet_self_links
  }
}

# DNS Zone for internal resolution
module "lb_internal_dns" {
  count      = var.lbs_configs.internal.enable ? 1 : 0
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/dns?ref=v55.1.0"
  project_id = var.project_id
  name       = var.name
  zone_config = {
    domain = "${var.lbs_configs.internal.domain}."
    private = {
      client_networks = [var.networking_config.vpc]
    }
  }
  recordsets = {
    ("A ${var.lbs_configs.internal.domain}") = {
      records = [module.lb_internal[0].address]
      ttl     = 300
    }
  }
  context = {
    networks = var.vpc_self_links
  }
}

# LB certificate
module "certificate_manager" {
  count      = var.lbs_configs.internal.enable ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-manager?ref=v55.1.0"
  project_id = var.project_id
  certificates = {
    (var.name) = {
      location = var.region
      managed = {
        domains         = [var.lbs_configs.internal.domain]
        issuance_config = var.name
      }
    }
  }
  issuance_configs = {
    (var.name) = {
      location                   = var.region
      ca_pool                    = module.cas[0].ca_pool_id
      key_algorithm              = "ECDSA_P256"
      lifetime                   = "1814400s"
      rotation_window_percentage = 34
    }
  }
}
