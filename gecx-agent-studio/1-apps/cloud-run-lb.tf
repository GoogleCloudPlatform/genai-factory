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

module "certificate-manager" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-manager?ref=v56.2.0"
  project_id = var.project_id
  certificates = {
    (var.name) = {
      location = var.region
      self_managed = {
        pem_certificate = file("${var.cloud_run_config.cert_bundle_path}/cert.pem")
        pem_private_key = file("${var.cloud_run_config.cert_bundle_path}/key.pem")
      }
    }
  }
}

module "address-ilb" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-address?ref=v56.2.0"
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
  source               = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-int?ref=v56.2.0"
  name                 = "${var.name}-internal-redirect"
  project_id           = var.project_id
  region               = var.region
  health_check_configs = {}
  address              = module.address-ilb.internal_addresses["ilb-01"].address
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
  source               = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-app-int?ref=v56.2.0"
  name                 = "${var.name}-internal"
  project_id           = var.project_id
  region               = var.region
  protocol             = "HTTPS"
  health_check_configs = {}
  address              = module.address-ilb.internal_addresses["ilb-01"].address
  backend_service_configs = {
    default = {
      port_name = ""
      backends = [
        { group = "${var.name}-internal" }
      ]
      health_checks = []
    }
  }
  neg_configs = {
    ("${var.name}-internal") = {
      cloudrun = {
        region = var.region
        target_service = {
          name = module.cloud-run.service_name
        }
      }
    }
  }
  https_proxy_config = {
    certificate_manager_certificates = [
      for k, v in module.certificate-manager.certificates : v.id
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
