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
  address = "https://discoveryengine.googleapis.com/v1/${module.ai-apps.search_engines["app"].name}/servingConfigs/default_search:search"
  query   = "FAST networking stage documentation"
}

output "commands" {
  description = "Command to run after the deployment."
  value       = <<EOT
  # Use this command to search something.

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

  # Alternatively, use the GUI to integrate the widget to your website
  # https://console.cloud.google.com/gen-app-builder/locations/global/engines/${var.name}-app/integration/widget?project=${var.project_config.id}
  EOT
}
