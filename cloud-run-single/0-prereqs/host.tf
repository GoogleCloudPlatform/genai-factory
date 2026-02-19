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
  source = "../../../cloud-foundation-fabric/modules/project-factory"
  count  = var.networking_config.create ? 1 : 0
  data_defaults = {
    billing_account = var.project_config.billing_account_id
    parent          = var.project_config.parent
    prefix          = var.project_config.prefix
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
  context = {
    iam_principals = {
      "service_accounts/service/iac-rw" = module.projects.service_accounts["service/iac-rw"].iam_email
      "service_agents/service/run"      = module.projects.service_agents["service/run"].iam_email
    }
  }
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v53.0.0"
  count      = var.networking_config.create ? 1 : 0
  project_id = module.project_host[0].projects.host.project_id
  name       = var.networking_config.vpc_id
  subnets = [
    merge(var.networking_config.subnet, { region = var.region })
  ]
  subnets_proxy_only = [
    merge(var.networking_config.subnet_proxy_only, { region = var.region })
  ]
  shared_vpc_host = true
  shared_vpc_service_projects = [
    module.projects.projects.service.project_id
  ]
}

# DNS policies for Google APIs
module "dns_policy_googleapis" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns-response-policy?ref=v53.0.0"
  count      = var.networking_config.create ? 1 : 0
  project_id = module.project_host[0].projects.host.project_id
  name       = "googleapis"
  factories_config = {
    rules = "./data/dns-policy-rules.yaml"
  }
  networks = { vpc = module.vpc[0].id }
}
