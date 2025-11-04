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

data "google_secret_manager_secret_version_access" "alloydb_initial_password" {
  project = var.project_config.id
  secret  = "alloydb-initial-postgres-password"
}

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
  }
  initial_user = {
    user     = "postgres"
    password = data.google_secret_manager_secret_version_access.alloydb_initial_password.secret_data
  }
  users = {
    # https://docs.cloud.google.com/alloydb/docs/database-users/manage-iam-auth#create-user
    # "For an IAM service account, supply the service account's address
    # without the .gserviceaccount.com suffix"
    (trimsuffix(var.service_accounts["project/gf-rrag-fe-0"].email, ".gserviceaccount.com")) = {
      type     = "ALLOYDB_IAM_USER"
      roles    = ["alloydbiamuser", "alloydbsuperuser"]
      roles    = ["alloydbiamuser"]
      password = null # password will be generated
    }
    (trimsuffix(var.service_accounts["project/gf-rrag-ing-0"].email, ".gserviceaccount.com")) = {
      type     = "ALLOYDB_IAM_USER"
      roles    = ["alloydbiamuser", "alloydbsuperuser"]
      password = null # password will be generated
    }
  }
  flags = {
    "alloydb.iam_authentication" = "on"
  }
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
  name    = var.name
  project = var.project_config.id
  region  = var.region
  target  = module.alloydb.service_attachment
  # need to override EXTERNAL default when target is a service attachment
  load_balancing_scheme   = ""
  network                 = local.vpc_id
  ip_address              = google_compute_address.psc_consumer_address.id
  allow_psc_global_access = true
}

module "psc_consumer_dns_zone" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns?ref=v46.0.0"
  project_id    = var.project_config.id
  name          = "${var.name}-alloydb"
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
