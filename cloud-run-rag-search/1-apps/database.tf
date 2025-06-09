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
  bigquery_id = replace(var.name, "-", "_")
}

module "bigquery-dataset" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/bigquery-dataset"
  project_id = var.project_config.id
  id         = local.bigquery_id
  tables = {
    (local.bigquery_id) = {
      friendly_name       = local.bigquery_id
      deletion_protection = var.enable_deletion_protection
    }
  }
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
  description         = "VertexAI index."
  index_update_method = "BATCH_UPDATE"

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

# resource "google_vertex_ai_index_endpoint_deployed_index" "index_deployment" {
#   deployed_index_id = var.name
#   display_name      = var.name
#   index             = google_vertex_ai_index.index.id
#   index_endpoint    = google_vertex_ai_index_endpoint.index_endpoint.id
# }
