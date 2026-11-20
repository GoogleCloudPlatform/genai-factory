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
  bigquery_id = replace(var.name, "-", "_")
}

module "bigquery-dataset" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/bigquery-dataset?ref=v60.0.0"
  project_id = var.project_id
  id         = local.bigquery_id
  tables = {
    (local.bigquery_id) = {
      friendly_name       = local.bigquery_id
      deletion_protection = var.enable_deletion_protection
    }
  }
}

module "psc_endpoint" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-psc-endpoint?ref=a578a3bc7f18e5befc0062ace51cf89fe10779df"
  project_id = var.project_id
  published_services = {
    (var.name) = {
      region     = var.region
      subnetwork = var.networking_config.subnet
      target     = module.cloudsql.psc_service_attachment_link
    }
  }
  context = {
    subnets = var.subnet_self_links
  }
}

module "dns_private_zone_cloudsql" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns?ref=a578a3bc7f18e5befc0062ace51cf89fe10779df"
  project_id    = var.project_id
  name          = "${var.name}-cloudsql"
  force_destroy = !var.enable_deletion_protection
  zone_config = {
    domain = module.cloudsql.dns_name
    private = {
      client_networks = [var.networking_config.vpc]
    }
  }
  recordsets = {
    "A " = {
      ttl     = 300
      records = ["$addresses:psc"]
    }
  }
  context = {
    addresses = {
      psc = module.psc_endpoint.addresses.published_services[var.name]
    }
    networks = var.vpc_self_links
  }
}

module "cloudsql" {
  source                        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloudsql-instance?ref=v60.0.0"
  project_id                    = var.project_id
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
      psc_config = {
        allowed_consumer_projects = [var.project_id]
      }
    }
  }
  databases = [
    var.name
  ]
  users = {
    (var.service_account_emails["service-01/gf-rrag-fe-0"]) = {
      type = "CLOUD_IAM_SERVICE_ACCOUNT"
    }
    (var.service_account_emails["service-01/gf-rrag-ing-0"]) = {
      type           = "CLOUD_IAM_SERVICE_ACCOUNT"
      database_roles = ["cloudsqlsuperuser"]
    }
  }
}
