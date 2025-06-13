# Copyright 2025 Google LLC
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
  name_to_underscores = replace(var.name, "-", "_")
}

module "index-bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs"
  project_id    = var.project_config.id
  prefix        = var.project_config.prefix
  name          = var.name
  location      = var.region
  versioning    = true
  force_destroy = !var.enable_deletion_protection
}

resource "google_vertex_ai_index" "index" {
  display_name        = var.name
  project             = var.project_config.id
  region              = var.region
  index_update_method = var.vertex_ai_index_config.index_update_method
  description         = "VertexAI index."

  metadata {
    contents_delta_uri = module.index-bucket.url

    config {
      dimensions                  = var.vertex_ai_index_config.dimensions
      approximate_neighbors_count = var.vertex_ai_index_config.approximate_neighbors_count
      shard_size                  = var.vertex_ai_index_config.shard_size
      distance_measure_type       = var.vertex_ai_index_config.distance_measure_type

      algorithm_config {

        tree_ah_config {
          leaf_node_embedding_count    = var.vertex_ai_index_config.algorithm_config.tree_ah_config.leaf_node_embedding_count
          leaf_nodes_to_search_percent = var.vertex_ai_index_config.algorithm_config.tree_ah_config.leaf_nodes_to_search_percent
        }
      }
    }
  }
}

resource "google_vertex_ai_index_endpoint" "index_endpoint" {
  display_name = var.name
  project      = var.project_config.id
  region       = var.region
  description  = "VertexAI index endpoint."

  private_service_connect_config {
    enable_private_service_connect = true
    project_allowlist = [
      var.project_config.id
    ]
  }
}

resource "google_vertex_ai_index_endpoint_deployed_index" "index_deployment" {
  deployed_index_id = local.name_to_underscores
  display_name      = var.name
  index             = google_vertex_ai_index.index.id
  index_endpoint    = google_vertex_ai_index_endpoint.index_endpoint.id
}

resource "google_compute_address" "vector_search_address" {
  name         = var.name
  project      = var.project_config.id
  address_type = "INTERNAL"
  subnetwork   = local.subnet_id
  region       = var.region
}

resource "google_compute_forwarding_rule" "vector_search_psc_endpoint" {
  name                  = var.name
  project               = var.project_config.id
  region                = var.region
  target                = google_vertex_ai_index_endpoint_deployed_index.index_deployment.private_endpoints[0].service_attachment
  load_balancing_scheme = ""
  network               = local.vpc_id
  ip_address            = google_compute_address.vector_search_address.id
}
