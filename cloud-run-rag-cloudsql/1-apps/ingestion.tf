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

module "cloud_run_ingestion" {
  source              = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-run-v2?ref=v55.4.0"
  project_id          = var.project_id
  type                = "JOB"
  name                = "${var.name}-ingestion"
  region              = var.region
  managed_revision    = false
  deletion_protection = var.enable_deletion_protection
  service_account_config = {
    create = false
    email  = var.service_account_emails["service-01/gf-rrag-ing-0"]
  }
  containers = merge({
    cloudsql-proxy = {
      image   = "gcr.io/cloud-sql-connectors/cloud-sql-proxy"
      command = ["/cloud-sql-proxy"]
      args = [
        module.cloudsql.connection_name,
        "--address",
        "0.0.0.0",
        "--port",
        "5432",
        "--psc",
        "--auto-iam-authn",
        "--health-check",
        "--structured-logs",
        "--http-address",
        "0.0.0.0"
      ]
    } },
    var.cloud_run_configs.ingestion.containers
  )
  iam = {
    "roles/run.invoker" = concat(
      ["serviceAccount:${var.service_account_emails["service-01/gf-rrag-ing-sched-0"]}"],
      var.cloud_run_configs.ingestion.service_invokers
    )
  }
  revision = {
    vpc_access = {
      egress  = var.cloud_run_configs.ingestion.vpc_access_egress
      network = var.networking_config.vpc
      subnet  = var.networking_config.subnet
      tags    = var.cloud_run_configs.ingestion.vpc_access_tags
    }
  }
  service_config = {
    gen2_execution_environment = true
    ingress                    = var.cloud_run_configs.ingestion.ingress
    scaling = {
      max_instance_count = var.cloud_run_configs.ingestion.max_instance_count
      min_instance_count = var.cloud_run_configs.ingestion.min_instance_count
    }
  }
  context = {
    iam_principals = local.iam_principals
    networks       = var.vpc_self_links
    subnets        = var.subnet_self_links
  }
}

resource "google_cloud_scheduler_job" "ingestion_scheduler" {
  name             = var.name
  description      = "Scheduler to periodically trigger the data ingestion."
  schedule         = var.ingestion_schedule_configs.schedule
  attempt_deadline = var.ingestion_schedule_configs.attempt_deadline
  region           = var.region
  project          = var.project_id

  retry_config {
    retry_count = var.ingestion_schedule_configs.retry_count
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${module.cloud_run_ingestion.job.name}:run"

    oauth_token {
      service_account_email = var.service_account_emails["service-01/gf-rrag-ing-sched-0"]
    }
  }
}
