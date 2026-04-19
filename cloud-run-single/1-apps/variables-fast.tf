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

# These values are automatically filled when using the FAST framework.
# Ignore if not used.

variable "service_accounts" {
  # tfdoc:variable:source 2-project-factory
  description = "The service accounts created for this stage."
  type = map(object({
    email     = string
    iam_email = string
    id        = string
  }))
  nullable = false
  default  = {}
}

variable "subnet_self_links" {
  # tfdoc:variable:source 2-networking
  description = "Shared VPCs subnet IDs."
  type        = map(map(string))
  nullable    = false
  default     = {}
}

variable "vpc_self_links" {
  # tfdoc:variable:source 2-networking
  description = "Shared VPC name => self link mappings."
  type        = map(string)
  nullable    = false
  default     = {}
}
