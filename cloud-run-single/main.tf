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

locals {
  project = module.projects.projects["project"]
}

module "projects" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project-factory?ref=fast-dev"
  data_defaults = {
    billing_account = var.project_config.billing_account_id
    parent          = var.project_config.parent
    prefix          = var.prefix
    project_reuse   = var.project_config.create ? null : {}
  }
  data_merges = {
    services = var.networking_config.create ? ["dns.googleapis.com"] : []
  }
  factories_config = {
    projects_data_path = "./projects"
  }
}

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
}

module "cloud_run" {
  source           = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2"
  project_id       = local.project.project_id
  name             = var.name
  region           = var.region
  ingress          = var.cloud_run_configs.ingress
  containers       = var.cloud_run_configs.containers
  service_account  = module.projects.service_accounts["project/gf-srun-0"].email
  managed_revision = false
  iam = {
    "roles/run.invoker" = var.cloud_run_configs.service_invokers
  }
  revision = {
    gen2_execution_environment = true
    max_instance_count         = var.cloud_run_configs.max_instance_count
    vpc_access = {
      egress  = var.cloud_run_configs.vpc_access_egress
      network = local.vpc_id
      subnet  = local.subnet_id
      tags    = var.cloud_run_configs.vpc_access_tags
    }
  }
  deletion_protection = var.enable_deletion_protection
}
