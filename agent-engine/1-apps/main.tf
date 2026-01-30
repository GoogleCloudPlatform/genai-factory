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

data "archive_file" "source" {
  type        = "tar.gz"
  source_dir  = "./apps/adk"
  output_path = "./${var.source_config.tar_gz_file_name}"
}

module "agent" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/agent-engine" #?ref=v51.0.0"
  name       = var.name
  project_id = var.project_config.id
  region     = var.region
  managed    = false
  agent_engine_config = {
    agent_framework = var.agent_engine_config.agent_framework
    class_methods   = var.agent_engine_config.class_methods
    environment_variables = {
      ENABLE_PSC_I  = var.agent_engine_config.enable_psc_i
      PROJECT_ID    = var.project_config.id
      PROXY_ADDRESS = local.proxy_ip
      PROXY_PORT    = var.networking_config.proxy_port
      REGION        = var.region
      # Enable ADK logging and tracing
      # For other frameworks see https://docs.cloud.google.com/agent-builder/agent-engine/manage/tracing#adk
      GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY         = tostring(var.agent_engine_config.enable_adk_telemetry),
      OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = tostring(var.agent_engine_config.enable_adk_msg_capture),
    }
    max_instances = var.agent_engine_config.max_instances
    min_instances = var.agent_engine_config.min_instances
  }
  bucket_config = {
    deletion_protection = var.enable_deletion_protection
    name                = "${var.prefix}-${var.name}"
  }
  deployment_files = {
    source_config = {
      entrypoint_module = var.source_config.entrypoint_module
      entrypoint_object = var.source_config.entrypoint_object
      source_path       = data.archive_file.source.output_path
    }
  }
  networking_config = {
    network_attachment_id = local.network_attachment_id
    dns_peering_configs = {
      "." = {
        target_network_name = local.vpc_name
      }
    }
  }
  service_account_config = {
    create = false
    email  = var.service_accounts["project/gf-ae-0"].email
  }
}
