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
  # An agent reaches the VPC either through its own PSC interface or
  # through the connectivity template of an Agent Gateway: the API
  # rejects the two together, so attaching a gateway turns PSC-I off.
  enable_psc_i = (
    !local.use_agent_gateways && var.network_attachment_id != null
  )
  iam_principals = {
    for k, v in var.service_accounts
    : k => v.email
  }
  use_agent_gateways = (
    var.agent_gateway_ids.egress != null
    || var.agent_gateway_ids.ingress != null
  )
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
  source                     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/geap-agent-runtime?ref=v59.0.0"
  name                       = var.name
  project_id                 = var.project_id
  region                     = var.region
  managed                    = false
  enable_deletion_protection = var.enable_deletion_protection
  agent_runtime_config = {
    agent_framework = var.agent_runtime_config.agent_framework
    class_methods = try(
      templatefile(var.agent_runtime_config.class_methods, {
        agent_name = var.name
        project_id = var.project_id
        region     = var.region
      }),
      var.agent_runtime_config.class_methods
    )
    environment_variables = {
      ENABLE_PSC_I       = local.enable_psc_i && var.agent_runtime_config.enable_psc_i
      FIRESTORE_DATABASE = var.name
      PROJECT_ID         = var.project_id
      PROXY_ADDRESS      = var.proxy_config.ip_address
      PROXY_PORT         = var.proxy_config.port
      REGION             = var.region
      # Enable ADK logging and tracing
      # For other frameworks see https://docs.cloud.google.com/agent-builder/agent-engine/manage/tracing#adk
      GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY         = tostring(var.agent_runtime_config.enable_adk_telemetry),
      OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = tostring(var.agent_runtime_config.enable_adk_msg_capture),
    }
    identity_type = "SERVICE_ACCOUNT"
    max_instances = var.agent_runtime_config.max_instances
    min_instances = var.agent_runtime_config.min_instances
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
    # Gateways governing the traffic to and from the runtime.
    agent_gateways = {
      egress  = var.agent_gateway_ids.egress
      ingress = var.agent_gateway_ids.ingress
    }
    network_attachment_id = local.enable_psc_i ? var.network_attachment_id : null
    dns_peering_configs = local.enable_psc_i ? {
      for k, v in var.dns_peering_configs : k => {
        target_network_name = coalesce(v.target_network_name, basename(var.networking_config.vpc))
        target_project_id   = coalesce(v.target_project_id, split("/", var.networking_config.vpc)[1])
      }
    } : {}
  }
  service_account_config = {
    create = false
    email  = var.service_account_emails["service-01/gf-ar-0"]
  }
  context = {
    iam_principals = local.iam_principals
    networks       = var.vpc_self_links
  }
}

module "firestore" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/firestore?ref=v59.0.0"
  project_id = var.project_id
  database = {
    name        = var.name
    type        = "FIRESTORE_NATIVE"
    location_id = var.region
  }
}
