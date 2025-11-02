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
  bigquery_id = replace(var.name, "-", "_")
}

module "bigquery-dataset" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/bigquery-dataset?ref=v46.0.0"
  project_id = var.project_config.id
  id         = local.bigquery_id
  tables = {
    (local.bigquery_id) = {
      friendly_name       = local.bigquery_id
      deletion_protection = var.enable_deletion_protection
    }
  }
}

# Networking resources for AlloyDB
/*
module "dns_private_zone_alloydb" {
  count         = var.create_alloydb ? 1 : 0
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns?ref=v46.0.0"
  project_id    = var.project_config.id
  name          = "${var.name}-alloydb"
  force_destroy = !var.enable_deletion_protection
  zone_config = {
    domain = module.alloydb[0].psc_dns_name
    private = {
      client_networks = [local.vpc_id]
    }
  }
  recordsets = {}
}

resource "google_dns_record_set" "alloydb_dns_record_set" {
  count        = var.create_alloydb ? 1 : 0
  project      = var.project_config.id
  managed_zone = module.dns_private_zone_alloydb[0].name
  name         = module.alloydb[0].psc_dns_name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.alloydb_address[0].address]
}

resource "google_compute_address" "alloydb_address" {
  count        = var.create_alloydb ? 1 : 0
  name         = "${var.name}-alloydb"
  project      = var.project_config.id
  address_type = "INTERNAL"
  subnetwork   = local.subnet_id
  region       = var.region
}

resource "google_compute_forwarding_rule" "alloydb_psc_endpoint" {
  count                 = var.create_alloydb ? 1 : 0
  name                  = "${var.name}-alloydb"
  project               = var.project_config.id
  region                = var.region
  target                = module.alloydb[0].service_attachment
  load_balancing_scheme = ""
  network               = local.vpc_id
  ip_address            = google_compute_address.alloydb_address[0].id
}

# this was still for sql
resource "google_compute_network_attachment" "psc_attachment" {
  name                  = var.name
  project               = var.project_config.id
  region                = var.region
  connection_preference = "ACCEPT_AUTOMATIC"
  subnetworks           = [local.subnet_id]
}
*/

module "alloydb" {
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/alloydb?ref=v46.0.0"
  project_id          = var.project_config.id
  project_number      = var.project_config.number
  cluster_name        = "alloydb"
  instance_name       = var.name
  location            = var.region
  deletion_protection = var.enable_deletion_protection
  network_config = {
    psc_config = { allowed_consumer_projects = [var.project_config.number] }
    # psa_config = { network = local.vpc_id }
  }
  # TODO: ???
  #  network_attachment_resource = google_compute_network_attachment.psc_attachment.id
  users = {
    # https://docs.cloud.google.com/alloydb/docs/database-users/manage-iam-auth#create-user
    # "For an IAM service account, supply the service account's address
    # without the .gserviceaccount.com suffix"
    (trimsuffix(var.service_accounts["project/gf-rrag-fe-0"].email, ".gserviceaccount.com")) = {
      type  = "ALLOYDB_IAM_USER"
      roles = ["alloydbiamuser", "alloydbsuperuser"] # TODO
      # roles    = ["alloydbsuperuser"] # TODO: nope, this did not help
      password = null # password will be generated
    }
    (trimsuffix(var.service_accounts["project/gf-rrag-ing-0"].email, ".gserviceaccount.com")) = {
      type  = "ALLOYDB_IAM_USER"
      roles = ["alloydbiamuser", "alloydbsuperuser"]
      # roles    = ["alloydbsuperuser"] # TODO: nope, this did not help
      password = null # password will be generated
    }
  }
  flags = {
    "alloydb.iam_authentication" = "on"
  }
  # TODO: ???
  #  depends_on = [
  #    google_compute_global_address.private_ip_alloc,
  #    google_service_networking_connection.default
  #  ]
}

# Create a PSC endpoint using the AlloyDB PSC attachment

resource "google_compute_address" "psc_consumer_address" {
  name         = var.name
  project      = var.project_config.id
  region       = var.region
  subnetwork   = local.subnet_id
  address_type = "INTERNAL"
}

resource "google_compute_forwarding_rule" "psc_consumer_fwd_rule" {
  name                    = var.name
  project                 = var.project_config.id
  region                  = var.region
  target                  = module.alloydb.service_attachment
  load_balancing_scheme   = "" # need to override EXTERNAL default when target is a service attachment
  network                 = local.vpc_id
  ip_address              = google_compute_address.psc_consumer_address.id
  allow_psc_global_access = true
}

module "psc_consumer_dns_zone" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns?ref=v46.0.0"
  project_id    = var.project_config.id
  name          = "${var.name}-alloydb" # TODO: check, it was just var.name
  description   = "DNS Zone for the PSC access to AlloyDB"
  force_destroy = !var.enable_deletion_protection
  zone_config = {
    domain = module.alloydb.psc_dns_name
    private = {
      client_networks = [local.vpc_id]
    }
  }
  recordsets = {}
}

resource "google_dns_record_set" "psc_consumer_dns_record" {
  name         = module.alloydb.psc_dns_name
  project      = var.project_config.id
  type         = "A"
  ttl          = 300
  managed_zone = module.psc_consumer_dns_zone.name
  rrdatas      = [google_compute_address.psc_consumer_address.address]
}
