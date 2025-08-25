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
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/bigquery-dataset?ref=v42.1.0"
  project_id = var.project_config.id
  id         = local.bigquery_id
  tables = {
    (local.bigquery_id) = {
      friendly_name       = local.bigquery_id
      deletion_protection = var.enable_deletion_protection
    }
  }
}

module "dns_private_zone_cloudsql" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns?ref=v42.1.0"
  project_id    = var.project_config.id
  name          = "${var.name}-cloudsql"
  force_destroy = !var.enable_deletion_protection
  zone_config = {
    domain = module.cloudsql.dns_name
    private = {
      client_networks = [local.vpc_id]
    }
  }
  recordsets = {}
}

resource "google_dns_record_set" "cloudsql_dns_record_set" {
  project      = var.project_config.id
  managed_zone = module.dns_private_zone_cloudsql.name
  name         = module.cloudsql.dns_name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.cloudsql_address.address]
}

resource "google_compute_address" "cloudsql_address" {
  name         = var.name
  project      = var.project_config.id
  address_type = "INTERNAL"
  subnetwork   = local.subnet_id
  region       = var.region
}

resource "google_compute_forwarding_rule" "cloudsql_psc_endpoint" {
  name                  = var.name
  project               = var.project_config.id
  region                = var.region
  target                = module.cloudsql.psc_service_attachment_link
  load_balancing_scheme = ""
  network               = local.vpc_id
  ip_address            = google_compute_address.cloudsql_address.id
}

module "cloudsql" {
  source                        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloudsql-instance?ref=v42.1.0"
  project_id                    = var.project_config.id
  gcp_deletion_protection       = var.enable_deletion_protection
  terraform_deletion_protection = var.enable_deletion_protection
  name                          = var.name
  region                        = var.region
  availability_type             = var.db_configs.availability_type
  database_version              = var.db_configs.database_version
  tier                          = var.db_configs.tier
  flags                         = var.db_configs.flags
  network_config = {
    connectivity = {
      psc_allowed_consumer_projects = [var.project_config.id]
    }
  }
  databases = [
    var.name
  ]
  users = {
    (var.service_accounts["project/gf-rrag-fe-0"].email) = {
      type = "CLOUD_IAM_SERVICE_ACCOUNT"
    }
    (var.service_accounts["project/gf-rrag-ing-0"].email) = {
      type = "CLOUD_IAM_SERVICE_ACCOUNT"
    }
  }
}
