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

# tfdoc:file:description Gemini Enterprise Custom MCP data connectors.

locals {
  gemini_enterprise_mcp_data_connectors = merge([
    for service_id, s in var.agent_registry_services : {
      for app_id in toset(coalesce(s.agent_gateway_app_ids, [])) :
      "${service_id}/${app_id}" => merge(s, {
        app_id        = app_id
        collection_id = trimsuffix(substr("${service_id}-${replace(app_id, "_", "-")}", 0, 54), "-")
        oauth_config  = try(coalesce(s.oauth_config, var.oauth_config), null)
        patch_body = jsonencode({
          actionConfig = {
            createBapConnection = true
            actionParams = merge(
              {
                agent_gateway_engine     = "projects/${var.number}/locations/${var.location}/collections/${try(var.gemini_enterprise_apps[app_id].collection_id, "default_collection")}/engines/${app_id}"
                auth_type                = try(coalesce(s.oauth_config, var.oauth_config), null) != null ? "OAUTH" : "NO_AUTH"
                instance_uri             = s.url
                mcp_server_source        = "BYO_MCP"
                use_agent_gateway_egress = true
              },
              try(coalesce(s.oauth_config, var.oauth_config), null) == null ? {} : {
                client_secret_basic_override = coalesce(s.oauth_config, var.oauth_config).client_secret_basic_override
                pkce_support_enabled         = coalesce(s.oauth_config, var.oauth_config).pkce_support_enabled
              },
              try(coalesce(s.oauth_config, var.oauth_config), null) == null ? {} : {
                for k, v in {
                  auth_uri        = coalesce(s.oauth_config, var.oauth_config).auth_uri
                  auth_uri_params = coalesce(s.oauth_config, var.oauth_config).auth_uri_params
                  client_id       = coalesce(s.oauth_config, var.oauth_config).client_id
                  client_secret   = coalesce(s.oauth_config, var.oauth_config).client_secret
                  scopes          = length(coalesce(s.oauth_config, var.oauth_config).scopes) > 0 ? join(" ", coalesce(s.oauth_config, var.oauth_config).scopes) : null
                  token_uri       = coalesce(s.oauth_config, var.oauth_config).token_uri
                } : k => v if v != null
              }
            )
          }
        })
        service_id = service_id
      })
    }
    if s.type == "mcp_server"
  ]...)
}

resource "google_discovery_engine_data_connector" "mcp" {
  for_each                = local.gemini_enterprise_mcp_data_connectors
  project                 = var.project_id
  location                = var.location
  collection_id           = each.value.collection_id
  collection_display_name = urlencode(coalesce(each.value.display_name, each.value.service_id))
  data_source             = "custom_mcp"
  connector_modes         = ["FEDERATED"]
  refresh_interval        = "86400s"
  static_ip_enabled       = false
  tag                     = each.value.collection_id
  deletion_policy         = local.deletion_policy

  # setUpDataConnectorV2 requires oauth_access_token in top-level params for
  # custom_mcp in FEDERATED mode, then overwrites params.instance_uri from
  # action_config.action_params.
  params = {
    oauth_access_token = "none"
  }

  entities {
    entity_name = "mcp_data"
  }

  action_config {
    create_bap_connection = true
    action_params = {
      auth_type         = "NO_AUTH"
      instance_uri      = each.value.url
      mcp_server_source = "BYO_MCP"
    }
  }

  lifecycle {
    precondition {
      condition     = contains(keys(var.gemini_enterprise_apps), each.value.app_id)
      error_message = "MCP data connector '${each.key}' references app '${each.value.app_id}', which is not in var.gemini_enterprise_apps."
    }
  }

  # Terraform destroys removed data_connector instances before updating
  # google_discovery_engine_search_engine in-place, and the Discovery Engine
  # API rejects deleting a DataConnector while its _mcp_data data store is
  # still listed on an Engine. Detach it from any engine first on destroy.
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      endpoint="https://${self.location == "global" ? "" : "${self.location}-"}discoveryengine.googleapis.com/v1"
      ds_id="${self.collection_id}_mcp_data"
      token="$(gcloud auth print-access-token)"
      lockdir="/tmp/ge-mcp-detach-${self.project}-${self.location}.lock"
      body=$(mktemp)
      resp=$(mktemp)

      while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 1
      done
      trap 'rmdir "$lockdir" 2>/dev/null || true; rm -f "$body" "$resp"' EXIT

      engines_url="$endpoint/projects/${self.project}/locations/${self.location}/collections/default_collection/engines"
      status=$(curl -sS \
        -H "Authorization: Bearer $token" \
        -H "X-Goog-User-Project: ${self.project}" \
        -o "$body" -w '%%{http_code}' \
        "$engines_url")

      if [[ "$status" == "404" ]]; then
        exit 0
      fi
      if [[ "$status" != 2* ]]; then
        echo "Failed to list Discovery Engine apps while detaching $ds_id (HTTP $status)" >&2
        cat "$body" >&2
        exit 1
      fi

      engines=$(jq -r --arg ds "$ds_id" '.engines[]? | select((.dataStoreIds // []) | index($ds)) | .name' "$body")
      for engine in $engines; do
        payload=$(jq -c --arg eng "$engine" --arg ds "$ds_id" \
          '.engines[] | select(.name == $eng) | ((.dataStoreIds // []) - [$ds]) as $rem | {dataStoreIds: (if ($rem | length) == 1 then [] else $rem end)}' "$body")
        patch_status=$(curl -sS -X PATCH \
          -H "Authorization: Bearer $token" \
          -H "Content-Type: application/json" \
          -H "X-Goog-User-Project: ${self.project}" \
          -d "$payload" \
          -o "$resp" -w '%%{http_code}' \
          "$endpoint/$engine?updateMask=dataStoreIds")
        if [[ "$patch_status" != 2* && "$patch_status" != "404" ]]; then
          echo "Failed to detach $ds_id from $engine (HTTP $patch_status)" >&2
          cat "$resp" >&2
          exit 1
        fi
      done
    EOT
  }
}

# google_discovery_engine_data_connector (provider 8.4.0) types
# action_config.action_params as map(string), so it serializes
# use_agent_gateway_egress as a string ("true"), which the Discovery Engine API
# ignores. We patch actionConfig via local-exec so use_agent_gateway_egress is
# sent as a JSON boolean along with agent_gateway_engine.
resource "terraform_data" "mcp_agent_gateway_patch" {
  for_each = local.gemini_enterprise_mcp_data_connectors

  triggers_replace = {
    connector     = google_discovery_engine_data_connector.mcp[each.key].name
    action_config = sha256(jsonencode(google_discovery_engine_data_connector.mcp[each.key].action_config))
    engine_app_id = each.value.app_id
    patch_body    = sha256(each.value.patch_body)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      endpoint="https://${var.location == "global" ? "" : "${var.location}-"}discoveryengine.googleapis.com/v1"
      url="$endpoint/${google_discovery_engine_data_connector.mcp[each.key].name}"
      mask="actionConfig"
      body=$(mktemp)
      trap 'rm -f "$body"' EXIT

      for attempt in {1..12}; do
        status=$(curl -sS -X PATCH \
          -H "Authorization: Bearer $(gcloud auth print-access-token)" \
          -H "Content-Type: application/json" \
          -H "X-Goog-User-Project: ${var.project_id}" \
          -d '${each.value.patch_body}' \
          -o "$body" -w '%%{http_code}' \
          "$url?updateMask=$mask")

        if [[ "$status" == 2* ]]; then
          exit 0
        fi
        if [[ "$status" == "400" ]] && grep -q "INITIALIZING" "$body"; then
          sleep 5
          continue
        fi
        break
      done

      echo "MCP data connector Agent Gateway patch failed for ${each.key} (HTTP $status)" >&2
      cat "$body" >&2
      exit 1
    EOT
  }

  depends_on = [
    terraform_data.app_agent_gateway_patch,
  ]
}
