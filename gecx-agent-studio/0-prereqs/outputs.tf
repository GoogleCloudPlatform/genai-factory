/**
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  buckets = {
    for k, v in module.projects.storage_buckets : k => v
  }
  networking_config = {
    host_project_number = try(local.projects["host"].number, null)
    subnet = coalesce(
      try(module.vpc[0].subnet_ids["${var.region}/${var.networking_config.subnet.name}"], null),
      "projects/${var.networking_config.host_project_id}/regions/${var.region}/subnetworks/${var.networking_config.subnet.name}"
    )
    vpc = coalesce(
      try(module.vpc[0].id, null),
      "projects/${var.networking_config.host_project_id}/global/networks/${var.networking_config.vpc_name}"
    )
  }
  projects = {
    for k, v in module.projects.projects : k => {
      id     = v.project_id
      number = v.number
    }
  }
  providers = {
    project_id      = local.projects["service-01"].id
    project_number  = local.projects["service-01"].number
    bucket          = local.buckets["service-01/iac-state"]
    service_account = local.service_accounts["service-01/iac-rw"].email
  }
  service_accounts = {
    for k, v in module.projects.service_accounts : k => {
      email     = v.email
      iam_email = v.iam_email
      id        = v.id
    }
  }
  tfvars = {
    enable_deletion_protection = var.enable_deletion_protection
    networking_config          = local.networking_config
    prefix                     = var.prefix
    project_id                 = local.projects["service-01"].id
    project_number             = local.projects["service-01"].number
    region                     = var.region
    service_account_emails = {
      for k, v in module.projects.service_accounts : k => v.email
    }
    service_account_ids = {
      for k, v in module.projects.service_accounts : k => v.id
    }
  }
}

output "buckets" {
  description = "Created buckets."
  value       = local.buckets
}

output "networking_config" {
  description = "The networking configuration."
  value       = local.networking_config
}

output "prefix" {
  description = "The unique name prefix to be used for all global unique resources."
  value       = var.prefix
}

output "projects" {
  description = "Created projects."
  value       = local.projects
}

output "service_accounts" {
  description = "Created service accounts."
  value       = local.service_accounts
}

resource "local_file" "providers" {
  file_permission = "0644"
  filename        = "../1-apps/providers.tf"
  content = templatefile(
    "templates/providers.tf.tpl",
    local.providers
  )
}

resource "local_file" "tfvars" {
  file_permission = "0644"
  filename        = "../1-apps/terraform.auto.tfvars"
  content = templatefile(
    "templates/terraform.auto.tfvars.tpl",
    local.tfvars
  )
}
