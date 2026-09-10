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

# Set custom service endpoints in Agent Registry
resource "google_agent_registry_service" "agent_registry_services" {
  for_each        = local.agent_registry_services
  project         = var.project_id
  location        = each.value.location
  service_id      = each.key
  display_name    = each.value.display_name
  description     = each.value.description
  deletion_policy = var.enable_deletion_protection ? "PREVENT" : "ABANDON"

  interfaces {
    url              = each.value.url
    protocol_binding = each.value.protocol
  }

  dynamic "agent_spec" {
    for_each = each.value.type == "agent" ? [""] : []
    content {
      type    = each.value.spec_type
      content = each.value.content
    }
  }

  dynamic "endpoint_spec" {
    for_each = each.value.type == "endpoint" ? [""] : []
    content {
      type = each.value.spec_type
    }
  }

  dynamic "mcp_server_spec" {
    for_each = each.value.type == "mcp_server" ? [""] : []
    content {
      type    = each.value.spec_type
      content = each.value.content
    }
  }
}
