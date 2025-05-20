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

# Managing external exposure

resource "google_compute_security_policy" "default" {
  name    = var.name
  project = local.project.project_id

  dynamic "rule" {
    for_each    = var.allowed_ip_ranges == null ? [] : [""]

    content {
      action   = "allow"
      priority = "100"
      description = "Allowed IP ranges."

      match {
        versioned_expr = "SRC_IPS_V1"

        config {
          src_ip_ranges = var.allowed_ip_ranges
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

resource "google_compute_global_address" "address" {
  count      = var.ip_address == null ? 1 : 0
  project    = local.project.project_id
  name       = var.name
  ip_version = "IPV4"
}

module "lb_external_redirect" {
  count               = var.expose_external == true ? 1 : 0
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-ext"
  project_id          = local.project.project_id
  name                = "${var.name}-redirect"
  use_classic_version = false
  forwarding_rules_config = {
    "" = {
      address = (
        var.ip_address == null
        ? google_compute_global_address.address[0].address
        : var.ip_address
      )
    }
  }
  health_check_configs = {}
  urlmap_config = {
    description = "URL redirect for glb-test-0."
    default_url_redirect = {
      https         = true
      response_code = "MOVED_PERMANENTLY_DEFAULT"
    }
  }
}

module "lb_external" {
  count               = var.expose_external == true ? 1 : 0
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-ext"
  project_id          = local.project.project_id
  name                = var.name
  use_classic_version = false
  protocol            = "HTTPS"
  forwarding_rules_config = {
    "" = {
      address = (
        var.ip_address == null
        ? google_compute_global_address.address[0].address
        : var.ip_address
      )
    }
  }
  backend_service_configs = {
    default = {
      port_name = ""
      backends = [
        { backend = var.name }
      ]
      health_checks   = []
      security_policy = google_compute_security_policy.default.id
    }
  }
  health_check_configs = {}
  neg_configs = {
    "${var.name}" = {
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
        domains = var.public_domains
      }
    }
  }
  depends_on = [
    module.cloud_run
  ]
}

# Managing internal exposure

## Cert Management

resource "google_privateca_ca_pool_iam_binding" "ccm-certificate-requester" {
  count     = var.expose_internal == true ? 1 : 0
  project   = local.project.project_id
  location  = var.region
  ca_pool   = module.cas[0].ca_pool_id
  role      = "roles/privateca.certificateRequester"
  members   = [
    "serviceAccount:service-${ local.project.number }@gcp-sa-certificatemanager.iam.gserviceaccount.com", 
  ]
}

module "certificate-manager" {
  count      = var.expose_internal == true ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-manager"
  project_id = local.project.project_id
  certificates = {
    "${var.name}" = {
      location        = var.region
      managed = {
        domains         = "${var.private_domains}"
        issuance_config = "${var.name}"
      }
    }
  }
  issuance_configs = {
    "${var.name}" = {
      location                   = var.region
      ca_pool                    = module.cas[0].ca_pool_id
      key_algorithm              = "ECDSA_P256"
      lifetime                   = "1814400s"
      rotation_window_percentage = 34
    }
  }
  depends_on=[
    google_privateca_ca_pool_iam_binding.ccm-certificate-requester
  ]
}

## ILB
module "ilb-l7" {
  count      = var.expose_internal == true ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-int"
  name       = var.name
  project_id = local.project.project_id
  region     = var.region
  backend_service_configs = {
    default = {
      port_name = ""
      backends = [
        { group = "internal-${var.name}" }
      ]
      health_checks   = []
      #security_policy = google_compute_security_policy.default.id
    }
  }
  health_check_configs = {}
  neg_configs = {
    "internal-${var.name}" = {
      cloudrun = {
        region = var.region
        target_service = {
          name = module.cloud_run.service_name
        }
      }
    }
  }
  protocol = "HTTPS"
  https_proxy_config = {
    certificate_manager_certificates = [for k,v in module.certificate-manager[0].certificates : v.id]
  }
  vpc_config = {
    network    = var.networking_config.vpc_id
    subnetwork = var.networking_config.subnet_id
  }
}

# DNS Zone for Internal resolution
module "private-dns" {
  count      = var.expose_internal == true ? 1 : 0
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/dns"
  project_id = local.project.project_id
  name       = var.name
  zone_config = {
    domain   = "${var.private_domains[0]}."
    private = {
      client_networks = [ module.vpc[0].id ]
    }
  }
  recordsets = {
    "A *" = { ttl = 300, records = [ module.ilb-l7.0.address ] }
    "A " = { ttl = 300, records = [ module.ilb-l7.0.address ] }
  }
}