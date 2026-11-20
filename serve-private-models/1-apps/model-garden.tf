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

resource "google_vertex_ai_endpoint_with_model_garden_deployment" "model_garden" {
  project  = var.project_id
  location = var.region
  publisher_model_name = (
    var.model_garden_config.hugging_face_model_id == null
    ? var.model_garden_config.publisher_model_name
    : null
  )
  hugging_face_model_id = var.model_garden_config.hugging_face_model_id

  model_config {
    accept_eula        = var.model_garden_config.accept_eula
    model_display_name = var.name
  }

  endpoint_config {
    endpoint_display_name = var.name
    private_service_connect_config {
      enable_private_service_connect = true
      project_allowlist              = [var.project_id]
    }
  }

  deploy_config {
    dedicated_resources {
      machine_spec {
        machine_type      = var.model_garden_config.machine_spec.machine_type
        accelerator_type  = var.model_garden_config.machine_spec.accelerator_type
        accelerator_count = var.model_garden_config.machine_spec.accelerator_count
      }
      min_replica_count = var.model_garden_config.min_replica_count
      max_replica_count = var.model_garden_config.max_replica_count
      spot              = var.model_garden_config.spot
    }
  }
}

# Create a PSC endpoint using the Model Garden PSC service attachment
module "psc_endpoint" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-psc-endpoint?ref=a578a3bc7f18e5befc0062ace51cf89fe10779df"
  project_id = var.project_id
  published_services = {
    (var.name) = {
      global_access = true
      region        = var.region
      subnetwork    = var.networking_config.subnet
      target = (
        google_vertex_ai_endpoint_with_model_garden_deployment.model_garden.endpoint_config[0].private_service_connect_config[0].service_attachment
      )
    }
  }
  context = {
    subnets = var.subnet_self_links
  }
}
