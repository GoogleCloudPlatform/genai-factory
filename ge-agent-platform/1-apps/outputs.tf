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


output "authz_extension_ids" {
  description = "Map of policy name to authorization service extension ID."
  value       = { for k, v in google_network_services_authz_extension.custom : k => v.id }
}

output "authz_policy_ids" {
  description = "Map of policy name to authorization policy ID."
  value       = { for k, v in google_network_security_authz_policy.custom : k => v.id }
}

output "service_extensions_sa" {
  description = "The Agent Gateway service extensions service account for Model Armor."
  value       = local.service_extensions_sa
}
