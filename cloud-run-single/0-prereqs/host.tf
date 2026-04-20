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

module "project_host" {
  count  = var.networking_config.create ? 1 : 0
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project-factory?ref=v55.1.0"
  data_defaults = {
    billing_account = var.project_config.billing_account_id
    parent          = var.project_config.parent
    prefix          = var.prefix
    bucket = {
      force_destroy = !var.enable_deletion_protection
    }
    locations = {
      storage = var.region
    }
  }
  factories_config = {
    basepath = "./data"
    paths = {
      projects = "projects/host"
    }
  }
  # Make the project_host module aware
  # of the service accounts and service agents created
  # through the project_service module
  context = {
    iam_principals = merge(
      {
        for k, v in module.project-service.service_account_iam_emails
        : "service_accounts/${k}" => v
      },
      {
        for k, v in module.project-service.service_agents
        : "service_agents/${k}" => v.iam_email
      }
    )
  }
}

module "vpc" {
  count      = var.networking_config.create ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v55.1.0"
  project_id = module.project_host[0].projects.host.project_id
  name       = var.networking_config.vpc_name
  subnets = [
    merge(var.networking_config.subnet, { region = var.region })
  ]
  subnets_proxy_only = [
    merge(var.networking_config.subnet_proxy_only, { region = var.region })
  ]
  shared_vpc_host = true
  shared_vpc_service_projects = [
    module.project-service.project_ids["service-01"]
  ]
}

# DNS policies for Google APIs
module "dns_policy_googleapis" {
  count      = var.networking_config.create ? 1 : 0
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns-response-policy?ref=v55.1.0"
  project_id = module.project_host[0].projects.host.project_id
  name       = "googleapis"
  factories_config = {
    rules = "./data/dns-policy-rules.yaml"
  }
  networks = { vpc = module.vpc[0].id }
}
