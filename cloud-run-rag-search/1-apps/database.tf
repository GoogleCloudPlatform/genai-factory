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
  vector_search_location = coalesce(
    var.vector_search_config.location,
    var.region == "europe-west1" ? "europe-west4" : var.region
  )
}

module "index-bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v59.2.0"
  project_id    = var.project_id
  prefix        = var.prefix
  name          = var.name
  location      = var.region
  versioning    = true
  force_destroy = !var.enable_deletion_protection
}

resource "google_vector_search_collection" "collection" {
  project       = var.project_id
  location      = local.vector_search_location
  collection_id = var.name
  display_name  = var.name
  description   = "Vector Search 2.0 collection."
  data_schema   = jsonencode(var.vector_search_config.data_schema)

  dynamic "vector_schema" {
    for_each = var.vector_search_config.vector_schema
    content {
      field_name = vector_schema.key

      dynamic "dense_vector" {
        for_each = vector_schema.value.dense_vector != null ? [vector_schema.value.dense_vector] : []
        content {
          dimensions = dense_vector.value.dimensions

          dynamic "vertex_embedding_config" {
            for_each = dense_vector.value.vertex_embedding_config != null ? [dense_vector.value.vertex_embedding_config] : []
            content {
              model_id      = vertex_embedding_config.value.model_id
              task_type     = vertex_embedding_config.value.task_type
              text_template = vertex_embedding_config.value.text_template
            }
          }
        }
      }

      dynamic "sparse_vector" {
        for_each = vector_schema.value.sparse_vector ? [1] : []
        content {}
      }
    }
  }
}

resource "google_vector_search_index" "index" {
  count           = var.vector_search_config.index_config.create ? 1 : 0
  project         = var.project_id
  location        = local.vector_search_location
  collection_id   = google_vector_search_collection.collection.collection_id
  index_id        = "${var.name}-index"
  display_name    = "${var.name}-index"
  description     = "Vector Search 2.0 ANN index."
  index_field     = var.vector_search_config.index_config.index_field
  distance_metric = var.vector_search_config.index_config.distance_metric
  filter_fields   = var.vector_search_config.index_config.filter_fields
  store_fields    = var.vector_search_config.index_config.store_fields

  dense_scann {
    feature_norm_type = var.vector_search_config.index_config.feature_norm_type
  }

  dedicated_infrastructure {
    mode = var.vector_search_config.index_config.mode
    autoscaling_spec {
      min_replica_count = var.vector_search_config.index_config.min_replica_count
      max_replica_count = var.vector_search_config.index_config.max_replica_count
    }
  }
}
