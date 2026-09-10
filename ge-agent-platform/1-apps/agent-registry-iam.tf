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

# tfdoc:file:description Agent Registry IAM bindings.

# Bindings on the whole Agent Registry.

resource "google_iap_agent_registry_iam_binding" "authoritative" {
  for_each = local.iam
  project  = var.project_id
  location = var.region
  role     = each.key
  members  = each.value
}

resource "google_iap_agent_registry_iam_binding" "bindings" {
  for_each = local.service_iam_bindings.registry
  project  = var.project_id
  location = var.region
  role     = each.value.role
  members  = each.value.members

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [""]
    content {
      expression  = each.value.condition.expression
      title       = each.value.condition.title
      description = each.value.condition.description
    }
  }
}

resource "google_iap_agent_registry_iam_member" "members" {
  for_each = local.service_iam_bindings_additive.registry
  project  = var.project_id
  location = var.region
  role     = each.value.role
  member   = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [""]
    content {
      expression  = each.value.condition.expression
      title       = each.value.condition.title
      description = each.value.condition.description
    }
  }
}

# Bindings on registered agents.

resource "google_iap_agent_registry_agent_iam_binding" "authoritative" {
  for_each = local.service_iam.agent
  project  = var.project_id
  location = var.region
  agent_id = each.value.id
  role     = each.value.role
  members  = each.value.members

  depends_on = [google_agent_registry_service.agent_registry_services]
}

resource "google_iap_agent_registry_agent_iam_binding" "bindings" {
  for_each = local.service_iam_bindings.agent
  project  = var.project_id
  location = var.region
  agent_id = each.value.id
  role     = each.value.role
  members  = each.value.members

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [""]
    content {
      expression  = each.value.condition.expression
      title       = each.value.condition.title
      description = each.value.condition.description
    }
  }

  depends_on = [google_agent_registry_service.agent_registry_services]
}

resource "google_iap_agent_registry_agent_iam_member" "members" {
  for_each = local.service_iam_bindings_additive.agent
  project  = var.project_id
  location = var.region
  agent_id = each.value.id
  role     = each.value.role
  member   = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [""]
    content {
      expression  = each.value.condition.expression
      title       = each.value.condition.title
      description = each.value.condition.description
    }
  }

  depends_on = [google_agent_registry_service.agent_registry_services]
}

# Bindings on registered endpoints.

resource "google_iap_agent_registry_endpoint_iam_binding" "authoritative" {
  for_each    = local.service_iam.endpoint
  project     = var.project_id
  location    = var.region
  endpoint_id = each.value.id
  role        = each.value.role
  members     = each.value.members

  depends_on = [google_agent_registry_service.agent_registry_services]
}

resource "google_iap_agent_registry_endpoint_iam_binding" "bindings" {
  for_each    = local.service_iam_bindings.endpoint
  project     = var.project_id
  location    = var.region
  endpoint_id = each.value.id
  role        = each.value.role
  members     = each.value.members

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [""]
    content {
      expression  = each.value.condition.expression
      title       = each.value.condition.title
      description = each.value.condition.description
    }
  }

  depends_on = [google_agent_registry_service.agent_registry_services]
}

resource "google_iap_agent_registry_endpoint_iam_member" "members" {
  for_each    = local.service_iam_bindings_additive.endpoint
  project     = var.project_id
  location    = var.region
  endpoint_id = each.value.id
  role        = each.value.role
  member      = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [""]
    content {
      expression  = each.value.condition.expression
      title       = each.value.condition.title
      description = each.value.condition.description
    }
  }

  depends_on = [google_agent_registry_service.agent_registry_services]
}

# Bindings on registered MCP servers.

resource "google_iap_agent_registry_mcp_server_iam_binding" "authoritative" {
  for_each      = local.service_iam.mcp_server
  project       = var.project_id
  location      = var.region
  mcp_server_id = each.value.id
  role          = each.value.role
  members       = each.value.members

  depends_on = [google_agent_registry_service.agent_registry_services]
}

resource "google_iap_agent_registry_mcp_server_iam_binding" "bindings" {
  for_each      = local.service_iam_bindings.mcp_server
  project       = var.project_id
  location      = var.region
  mcp_server_id = each.value.id
  role          = each.value.role
  members       = each.value.members

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [""]
    content {
      expression  = each.value.condition.expression
      title       = each.value.condition.title
      description = each.value.condition.description
    }
  }

  depends_on = [google_agent_registry_service.agent_registry_services]
}

resource "google_iap_agent_registry_mcp_server_iam_member" "members" {
  for_each      = local.service_iam_bindings_additive.mcp_server
  project       = var.project_id
  location      = var.region
  mcp_server_id = each.value.id
  role          = each.value.role
  member        = each.value.member

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [""]
    content {
      expression  = each.value.condition.expression
      title       = each.value.condition.title
      description = each.value.condition.description
    }
  }

  depends_on = [google_agent_registry_service.agent_registry_services]
}
