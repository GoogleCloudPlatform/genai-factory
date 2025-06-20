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
  address = "https://discoveryengine.googleapis.com/v1/${module.agentspace.search_engines["app"].name}/servingConfigs/default_search:search"
  query   = "fast networking stage"
}

output "commands" {
  description = "Run this command to search something."
  value       = <<EOT

# For widget configuration (including CORS) head to
# https://console.cloud.google.com/gen-app-builder/locations/${var.region}/engines/${module.agentspace.search_engines["app"].display_name}/integration/widget

# For REST, use this command to search something
curl -X POST ${local.address} \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "${local.query}",
    "pageSize": 10,
    "queryExpansionSpec": {
      "condition": "AUTO"
    },
    "spellCorrectionSpec": {
      "mode": "AUTO"
    },
    "languageCode": "en-US",
    "userInfo": {
      "timeZone": "Europe/Rome"
    }
  }'
EOT
}
