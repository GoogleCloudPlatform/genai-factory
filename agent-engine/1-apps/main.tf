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
  agent_files = [
    for f in fileset(var.source_config.app_path, "**") : f
    if length(regexall("(?:^|/)(?:__pycache__|\\.venv|\\.DS_Store)(?:$|/)|\\.pyc$|\\.pyo$", f)) == 0
  ]
  iam_principals = {
    for k, v in var.service_accounts
    : k => v.email
  }
  tar_gz_file_name = "${sha1(join("", [
    for f in local.agent_files
    : filesha1("${var.source_config.app_path}/${f}")
  ]))}.tar.gz"
}

data "archive_file" "source" {
  type        = "tar.gz"
  source_dir  = var.source_config.app_path
  output_path = "./${local.tar_gz_file_name}"
  excludes    = ["__pycache__", "src/__pycache__", ".venv", ".DS_Store"]
}

module "agent" {
  source                     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/agent-engine?ref=v57.0.0"
  name                       = var.name
  project_id                 = var.project_id
  region                     = var.region
  managed                    = false
  enable_deletion_protection = var.enable_deletion_protection
  agent_engine_config = {
    agent_framework = var.agent_engine_config.agent_framework
    class_methods = try(
      templatefile(var.agent_engine_config.class_methods, {
        agent_name = var.name
        project_id = var.project_id
        region     = var.region
      }),
      var.agent_engine_config.class_methods
    )
    environment_variables = {
      ENABLE_PSC_I       = var.agent_engine_config.enable_psc_i
      FIRESTORE_DATABASE = var.name
      PROJECT_ID         = var.project_id
      PROXY_ADDRESS      = var.proxy_config.ip_address
      PROXY_PORT         = var.proxy_config.port
      REGION             = var.region
      # Enable ADK logging and tracing
      # For other frameworks see https://docs.cloud.google.com/agent-builder/agent-engine/manage/tracing#adk
      GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY         = tostring(var.agent_engine_config.enable_adk_telemetry),
      OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = tostring(var.agent_engine_config.enable_adk_msg_capture),
    }
    identity_type = "SERVICE_ACCOUNT"
    max_instances = var.agent_engine_config.max_instances
    min_instances = var.agent_engine_config.min_instances
  }
  bucket_config = {
    deletion_protection = var.enable_deletion_protection
    name                = "${var.prefix}-${var.name}"
  }
  deployment_config = {
    source_files_config = {
      source_path = data.archive_file.source.output_path
      python_spec = {
        entrypoint_module = var.source_config.entrypoint_module
        entrypoint_object = var.source_config.entrypoint_object
      }
    }
  }
  networking_config = {
    network_attachment_id = var.network_attachment_id
    dns_peering_configs = {
      for k, v in var.dns_peering_configs : k => {
        target_network_name = coalesce(v.target_network_name, basename(var.networking_config.vpc))
        target_project_id   = coalesce(v.target_project_id, split("/", var.networking_config.vpc)[1])
      }
    }
  }
  service_account_config = {
    create = false
    email  = var.service_account_emails["service-01/gf-ae-0"]
  }
  context = {
    iam_principals = local.iam_principals
    networks       = var.vpc_self_links
  }
}

module "firestore" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/firestore?ref=v57.0.0"
  project_id = var.project_id
  database = {
    name        = var.name
    type        = "FIRESTORE_NATIVE"
    location_id = var.region
  }
}
