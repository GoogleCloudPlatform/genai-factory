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
resource "google_compute_region_security_policy" "security_policy_external_regional" {
  count   = var.lbs_config.external_regional.enable ? 1 : 0
  name    = "${var.name}-external-regional"
  region  = var.region
  project = var.project_config.id
  type    = "CLOUD_ARMOR"

  dynamic "rules" {
    for_each = (
      try(length(var.lbs_config.external_regional.allowed_ip_ranges), 0) > 0 ? [""] : []
    )

    content {
      action      = "allow"
      priority    = "100"
      description = "Allowed source IP ranges."

      match {
        versioned_expr = "SRC_IPS_V1"

        config {
          src_ip_ranges = var.lbs_config.external_regional.allowed_ip_ranges
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

resource "google_compute_address" "address_external_regional" {
  count = (
    var.lbs_config.external_regional.enable &&
    var.lbs_config.external_regional.ip_address == null
    ? 1 : 0
  )
  project      = var.project_config.id
  name         = "${var.name}-external"
  ip_version   = "IPV4"
  region       = var.region
  network_tier = "STANDARD"
}

module "lb_external_regional_redirect" {
  count      = var.lbs_config.external_regional.enable ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-ext-regional"
  project_id = var.project_config.id
  name       = "${var.name}-external-regional-redirect"
  region     = var.region
  vpc        = local.vpc_id
  address = coalesce(
    var.lbs_config.external_regional.ip_address,
    google_compute_address.address_external_regional[0].address
  )
  health_check_configs = {}
  urlmap_config = {
    description = "HTTP to HTTPS redirect."
    default_url_redirect = {
      https         = true
      response_code = "MOVED_PERMANENTLY_DEFAULT"
    }
  }
}

# Regional external application LB only supports managed certificates created with Certificate Manager 

# DNS authorization
resource "google_certificate_manager_dns_authorization" "dns_authorizations" {
  project  = var.project_config.id
  name     = "external-regional"
  location = var.region
  type     = "PER_PROJECT_RECORD"
  domain   = var.lbs_config.external_regional.domain
}

# Certificate Manager certificate creation
resource "google_certificate_manager_certificate" "certificates" {
  project  = var.project_config.id
  name     = "external-regional-cert"
  location = var.region

  managed {
    domains            = [var.lbs_config.external_regional.domain]
    dns_authorizations = [google_certificate_manager_dns_authorization.dns_authorizations.id]
  }
}

module "lb_external_regional" {
  count      = var.lbs_config.external_regional.enable ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-ext-regional"
  project_id = var.project_config.id
  name       = "${var.name}-external-regional"
  region     = var.region
  vpc        = local.vpc_id
  protocol   = "HTTPS"
  address = coalesce(
    var.lbs_config.external_regional.ip_address,
    google_compute_address.address_external_regional[0].address
  )
  backend_service_configs = {
    default = {
      port_name = ""
      backends = [
        { backend = "${var.name}-external-regional" }
      ]
      health_checks = []
<<<<<<< HEAD
      # TODO troubleshoot Cloud Armor
      # security_policy = google_compute_region_security_policy.security_policy_external_regional[0].id
=======
      # Not supported with service extensions? security_policy = google_compute_region_security_policy.security_policy_external_regional[0].id
>>>>>>> a97748d508df2b30dbead9e5cb3b87322e4f3bc3
    }
  }
  health_check_configs = {}
  neg_configs = {
    ("${var.name}-external-regional") = {
      cloudrun = {
        region = var.region
        target_service = {
          name = module.cloud_run.service_name
        }
      }
    }
  }
  https_proxy_config = {
    certificate_manager_certificates = [google_certificate_manager_certificate.certificates.id]
  }
}

resource "google_network_services_lb_traffic_extension" "traffic_ext" {
  count    = var.lbs_config.external_regional.enable ? 1 : 0
  name     = "l7-elb-traffic-ext"
  project  = var.project_config.id
  location = var.region

  load_balancing_scheme = "EXTERNAL_MANAGED"
  forwarding_rules      = [module.lb_external_regional[0].forwarding_rule.id]

  extension_chains {
    name = "chain-model-armor"

    match_condition {
      cel_expression = "request.host == '${var.lbs_config.external_regional.domain}'"
    }

    extensions {
      name      = "ext11"
      authority = "ext11.com"
      service   = "modelarmor.${var.region}.rep.googleapis.com"
      timeout   = "0.1s"
      fail_open = false

      supported_events = ["REQUEST_HEADERS"]
      forward_headers  = ["custom-header"]
      metadata = {
        model_armor_settings = <<EOT
          [
            {
              "model" : "default",
              "model_response_template_id" : "${google_model_armor_template.model-armor-template.id}",
              "user_prompt_template_id" : "${google_model_armor_template.model-armor-template.id}"
            }
          ]
          EOT
      }
    }
  }
}