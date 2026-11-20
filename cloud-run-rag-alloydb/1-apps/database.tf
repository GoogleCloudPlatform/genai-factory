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

module "alloydb" {
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/alloydb?ref=v60.0.0"
  project_id          = var.project_id
  project_number      = var.number
  cluster_name        = "alloydb"
  instance_name       = var.name
  location            = var.region
  deletion_protection = var.enable_deletion_protection
  network_config = {
    psc_config = { allowed_consumer_projects = [var.number] }
  }
  users = {
    # https://docs.cloud.google.com/alloydb/docs/database-users/manage-iam-auth#create-user
    # "For an IAM service account, supply the service account's address
    # without the .gserviceaccount.com suffix"
    (trimsuffix(var.service_account_emails["service-01/gf-rrag-fe-0"], ".gserviceaccount.com")) = {
      type     = "ALLOYDB_IAM_USER"
      roles    = ["alloydbiamuser"]
      password = null # password will be generated
    }
    (trimsuffix(var.service_account_emails["service-01/gf-rrag-ing-0"], ".gserviceaccount.com")) = {
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
module "psc_endpoint" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-psc-endpoint?ref=a578a3bc7f18e5befc0062ace51cf89fe10779df"
  project_id = var.project_id
  published_services = {
    (var.name) = {
      global_access = true
      region        = var.region
      subnetwork    = var.networking_config.subnet
      target        = module.alloydb.service_attachment
    }
  }
  context = {
    subnets = var.subnet_self_links
  }
}

module "psc_consumer_dns_zone" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns?ref=a578a3bc7f18e5befc0062ace51cf89fe10779df"
  project_id    = var.project_id
  name          = "${var.name}-alloydb"
  description   = "DNS Zone for the PSC access to AlloyDB"
  force_destroy = !var.enable_deletion_protection
  zone_config = {
    domain = module.alloydb.psc_dns_name
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
