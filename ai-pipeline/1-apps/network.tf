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
  subnet_id = (
    var.networking_config.create
    ? module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
    : var.networking_config.subnet.name
  )
  vpc_id = (
    var.networking_config.create
    ? module.vpc[0].id
    : var.networking_config.vpc_id
  )
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v51.0.0"
  count      = var.networking_config.create ? 1 : 0
  project_id = var.project_config.id
  name       = var.networking_config.vpc_id
  subnets = [
    merge(var.networking_config.subnet, { region = var.region })
  ]
  subnets_proxy_only = [
    merge(var.networking_config.subnet_proxy_only, { region = var.region })
  ]
}

# DNS policies for Google APIs
module "dns_policy_googleapis" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns-response-policy?ref=v51.0.0"
  count      = var.networking_config.create ? 1 : 0
  project_id = var.project_config.id
  name       = "googleapis"
  factories_config = {
    rules = "./data/dns-policy-rules.yaml"
  }
  networks = { (var.name) = module.vpc[0].id }
}

# Network Attachment for Private Vertex AI pipeline
resource "google_compute_network_attachment" "pipeline_attachment" {
  name                  = "pipeline-attachment"
  project               = var.project_config.id
  region                = var.region
  connection_preference = "ACCEPT_AUTOMATIC"
  subnetworks           = [module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]]
}

# Secure Web Proxy 

# Internal IP for the Proxy
resource "google_compute_address" "swp_address" {
  name         = "secure-web-proxy"
  region       = var.region
  subnetwork   = module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
  address_type = "INTERNAL"
  project      = var.project_config.id
}

module "secure-web-proxy" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-swp?ref=v51.0.0"
  project_id = var.project_config.id
  region     = var.region
  name       = "secure-web-proxy"
  network    = module.vpc[0].id
  subnetwork = module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"]
  gateway_config = {
    addresses = [google_compute_address.swp_address.address]
  }
  certificates = [module.certificate-manager.certificates["swp-cert"].id]
  policy_rules = {
    allow-all = {
      priority        = 1000
      allow           = true
      session_matcher = "true"
    }
  }
}

# Create a self-signed certificate for the Proxy
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "cert" {
  private_key_pem = tls_private_key.private_key.private_key_pem
  subject {
    common_name  = "swp.proxy.internet"
    organization = "GenAI Factory"
  }
  validity_period_hours = 720
  dns_names             = ["swp.proxy.internet"]
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

module "certificate-manager" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-manager?ref=v51.0.0"
  project_id = var.project_config.id
  certificates = {
    swp-cert = {
      location = var.region
      self_managed = {
        pem_certificate = tls_self_signed_cert.cert.cert_pem
        pem_private_key = tls_private_key.private_key.private_key_pem
      }
    }
  }
}

# DNS Zone for Proxy
resource "google_dns_managed_zone" "proxy_zone" {
  name        = "proxy-internet"
  dns_name    = "proxy.internet."
  description = "Private zone for Proxy"
  project     = var.project_config.id
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = module.vpc[0].id
    }
  }
}

resource "google_dns_record_set" "swp_record" {
  name         = "swp.${google_dns_managed_zone.proxy_zone.dns_name}"
  managed_zone = google_dns_managed_zone.proxy_zone.name
  type         = "A"
  ttl          = 300
  project      = var.project_config.id
  rrdatas      = [google_compute_address.swp_address.address]
}