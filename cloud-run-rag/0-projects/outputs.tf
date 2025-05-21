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
    for k, v in module.projects.buckets : k => v
  }
  project_data = flatten([
    for k, v in module.projects.projects : [
      for sk, sv in try(v.automation.service_accounts) : {
        key             = "${k}-${sk}"
        bucket          = try(v.automation.bucket, null)
        project_id      = v.project_id
        project_number  = v.number
        service_account = sv
      }
    ] if try(v.automation.bucket, null) != null
  ])
  projects = {
    for k, v in module.projects.projects : k => {
      id         = v.project_id
      number     = v.number
      automation = v.automation
    }
  }
  service_accounts = {
    for k, v in module.projects.service_accounts : k => {
      email     = v.email
      iam_email = v.iam_email
      id        = v.id
    }
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
  for_each        = { for v in local.project_data : v.key => v }
  file_permission = "0644"
  filename        = "../1-apps/providers.tf"
  content         = templatefile("templates/providers.tf.tpl", each.value)
}

resource "local_file" "tfvars" {
  file_permission = "0644"
  filename        = "../1-apps/terraform.auto.tfvars"
  content = templatefile(
    "templates/terraform.auto.tfvars.tpl",
    {
      projects         = local.projects
      buckets          = local.buckets
      service_accounts = local.service_accounts
    }
  )
}
