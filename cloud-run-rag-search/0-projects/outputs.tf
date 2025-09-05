/**
 * Copyright 2025 Google LLC
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
  projects = {
    for k, v in module.projects.projects : k => {
      id     = v.project_id
      number = v.number
      prefix = var.project_config.prefix
    }
  }
  providers = {
    bucket          = local.buckets["project/iac-state"]
    project_id      = local.projects.project.id
    project_number  = local.projects.project.number
    service_account = local.service_accounts["project/iac-rw"].email
  }
  service_accounts = {
    for k, v in module.projects.service_accounts : k => {
      email     = v.email
      iam_email = v.iam_email
      id        = v.id
    }
  }
  tfvars = {
    projects         = local.projects
    buckets          = local.buckets
    service_accounts = local.service_accounts
  }
}

output "buckets" {
  description = "Created buckets."
  value       = local.buckets
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
