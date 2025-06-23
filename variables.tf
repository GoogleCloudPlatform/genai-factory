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

variable "bucket_configs" {
  description = "The GCS bucket configurations where embeddings are stored."
  type = object({
    bucket_name         = string
    embedding_data_path = string
  })
  nullable = false
}

variable "enable_access_logging" {
  description = "Whether to enable access logging for the private endpoint."
  type        = bool
  nullable    = false
  default     = true
}

variable "labels" {
  description = "Labels to associate to resources."
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "The name to give to resources."
  type        = string
  nullable    = false
  default     = "vector"
}

variable "networking_configs" {
  description = "The networking configurations (PSA, PSC)."
  type = object({
    connection_type = optional(string, "psc")
    psa_configs = optional(object({
      network_id       = string
      psa_ranges       = list(string)
      deployment_group = optional(string, "default")
    }))
    psc_configs = optional(object({
    }))
  })
  nullable = false
  validation {
    condition = contains(
      ["psa", "psc", "public"],
      var.networking_configs.connection_type
    )
    error_message = "Invalid value for networking_configs.connection_type. Must be one of: psa, psc, public."
  }
}

variable "project_id" {
  type        = string
  description = "The project id where resources will be created."
}

variable "region" {
  type        = string
  description = "The region where resources will be created."
}

variable "vector_endpoint_configs" {
  description = "The Vector Search index endpoint configurations."
  type = object({
    description = optional(string, "Terraform managed.")
    # in main do
    # coalesce(var.vector_endpoint_configs.display_name, var.name)
    display_name = optional(string)
    index_deployments = map(object({
      auth_configs = optional(object({
        allowed_issuers = optional(list(string), [])
        audiences       = optional(list(string), [])
      }))
      id            = string
      resource_type = optional(string, "dedicated")
      resource_configs = optional(object({
        machine_type = optional(string, "e2-highmem-16")
        max_replicas = optional(number, 3)
        min_replicas = optional(number, 1)
      }), {})
    }))
    timeout_configs = optional(object({
      create = optional(string, "6h")
      delete = optional(string, "5h")
      update = optional(string, "1h")
    }))
  })
  nullable = false
  default  = {}
  validation {
    condition     = contains(["automatic", "dedicated"], var.vector_endpoint_configs.index_deployments.resource_type)
    error_message = "Invalid value for vector_endpoint_configs.index_deployments.resource_type. Must be automatic or dedicated."
  }
}

variable "vector_index_configs" {
  description = "The index configurations."
  type = object({
    dimentions                  = number
    display_name                = string
    id                          = string
    algorithm_config_type       = optional(string, "tree_ah_config")
    approximate_neighbors_count = optional(number, 150)
    description                 = optional(string, "Terraform managed.")
    distance_measure_type       = optional(string, "COSINE_DISTANCE")
    feature_norm_type           = optional(string, "UNIT_L2_NORM")
    index_shard_size            = optional(string, "SHARD_SIZE_MEDIUM")
    timeout_configs = optional(object({
      create = optional(string, "6h")
      delete = optional(string, "5h")
      update = optional(string, "1h")
    }))
    tree_ah_leaf_nodes_configs = optional(object({
      embedding_count   = optional(number, 1000)
      to_search_percent = optional(number, 10)
    }), {})
    update_method = optional(string, "BATCH_UPDATE")
  })
  nullable = false
  default  = {}
  validation {
    condition = contains(
      ["SHARD_SIZE_LARGE", "SHARD_SIZE_MEDIUM", "SHARD_SIZE_SMALL"],
      var.vector_index_configs.shard_size
    )
    error_message = "Invalid value for vector_index_configs.shard_size. Must be one of: SHARD_SIZE_SMALL, SHARD_SIZE_MEDIUM, SHARD_SIZE_LARGE."
  }
  validation {
    condition = contains(
      ["COSINE_DISTANCE", "DOT_PRODUCT_DISTANCE", "L2_SQUARED_DISTANCE"],
      var.vector_index_configs.distance_measure_type
    )
    error_message = "Invalid value for vector_index_configs.index_distance_measure_type. Must be one of: DOT_PRODUCT_DISTANCE, COSINE_DISTANCE, L2_SQUARED_DISTANCE."
  }
  validation {
    condition = contains(
      ["NONE", "UNIT_L2_NORM"],
      var.vector_index_configs.feature_norm_type
    )
    error_message = "Invalid value for vector_index_configs.feature_norm_type. Must be one of: NONE, UNIT_L2_NORM."
  }
  validation {
    condition = contains(
      ["brute_force_config", "tree_ah_config"],
      var.vector_index_configs.algorithm_config_type
    )
    error_message = "Invalid value for vector_index_configs.algorithm_config_type. Must be one of: brute_force_config, tree_ah_config."
  }
  validation {
    condition = contains(
      ["BATCH_UPDATE", "STREAM_UPDATE"],
      var.vector_index_configs.update_method
    )
    error_message = "Invalid value for vector_index_configs.update_method. Must be one of: BATCH_UPDATE, STREAM_UPDATE."
  }
}
