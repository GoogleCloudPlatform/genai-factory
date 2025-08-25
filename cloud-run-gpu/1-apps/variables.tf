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

variable "cloud_run_configs" {
  description = "The Cloud Run configurations."
  type = object({
    containers = optional(map(any), {
      gemma = {
        image = "us-docker.pkg.dev/cloudrun/container/gemma/gemma3-1b:latest"
        env = {
          OLLAMA_NUM_PARALLEL = "4"
          PORT                = 8081
        }
        ports = {}
        resources = {
          limits = {
            cpu              = "4"
            memory           = "16Gi"
            "nvidia.com/gpu" = "1"
          }
        }
      }
      chat-ui = {
        image = "us-docker.pkg.dev/google-samples/containers/gke/gradio-app:v1.0.4"
        ports = {
          default = {
            container_port = 7860
          }
        }
        env = {
          CONTEXT_PATH = "/v1/chat/completions"
          HOST         = "http://localhost:8081"
          LLM_ENGINE   = "openai-chat"
          MODEL_ID     = "gemma3:1b"
        }
        resources = {
          limits = {
            cpu    = "500m"
            memory = "256Mi"
          }
        }
      }
    })
    ingress                       = optional(string, "INGRESS_TRAFFIC_ALL")
    max_instance_count            = optional(number, 3)
    service_invokers              = optional(list(string), [])
    vpc_access_egress             = optional(string, "ALL_TRAFFIC")
    vpc_access_tags               = optional(list(string), [])
    gpu_zonal_redundancy_disabled = optional(bool, true)
    node_selector = optional(map(string), {
      accelerator = "nvidia-l4"
    })
  })
  nullable = false
  default  = {}
}

variable "enable_deletion_protection" {
  description = "Whether deletion protection should be enabled."
  type        = bool
  nullable    = false
  default     = true
}

variable "name" {
  description = "The name of the resources. This is also the project suffix if a new project is created."
  type        = string
  nullable    = false
  default     = "gf-rgpu-0"
}

variable "project_config" {
  description = "The project where to create the resources."
  type = object({
    id     = string
    number = string
  })
  nullable = false
}

variable "region" {
  type        = string
  description = "The GCP region where to deploy the resources."
  nullable    = false
  default     = "europe-west1"
}

variable "service_accounts" {
  description = "The pre-created service accounts used by the blueprint."
  type = map(object({
    email     = string
    iam_email = string
    id        = string
  }))
  default = {}
}
