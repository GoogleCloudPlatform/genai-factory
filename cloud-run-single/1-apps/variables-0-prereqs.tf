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

variable "enable_deletion_protection" {
  description = "Whether deletion protection should be enabled."
  type        = bool
  nullable    = false
  default     = true
}

variable "networking_config" {
  description = "The networking configuration."
  type = object({
    subnet_id = string
    vpc_id    = string
  })
  nullable = false
}

variable "projects" {
  description = "The projects where to create the resources."
  type = object({
    host = object({
      id     = string
      number = string
    })
    service = object({
      id     = string
      number = string
    })
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
  description = "The pre-created service accounts."
  type = map(object({
    email     = string
    iam_email = string
    id        = string
  }))
  nullable = false
}
