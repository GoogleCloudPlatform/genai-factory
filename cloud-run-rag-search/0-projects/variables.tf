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

variable "enable_iac_sa_impersonation" {
  description = "Whether the user running this module should be granted serviceAccountTokenCreator on the automation service account."
  type        = bool
  default     = true
}

variable "project_config" {
  description = "The project configuration."
  type = object({
    billing_account_id = optional(string)     # if create or control equal true
    control            = optional(bool, true) # to control an existing project
    create             = optional(bool, true) # to create the project
    parent             = optional(string)     # if control equals true
    prefix             = optional(string)     # the prefix of the project name
  })
  nullable = false
  validation {
    condition = (
      var.project_config.parent == null ||
      can(regex("(organizations|folders)/[0-9]+", var.project_config.parent))
    )
    error_message = "Parent must be of the form folders/folder_id or organizations/organization_id."
  }
}

variable "region" {
  description = "The region where to create the buckets."
  type        = string
  default     = "europe-west1"
}
