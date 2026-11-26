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

# tfdoc:file:description Native Discovery Engine data stores, schemas, and SaaS/MCP data connectors.

locals {
  gemini_enterprise_data_connectors = {
    for k, v in var.gemini_enterprise_data_connectors : k => merge(v, {
      collection_id = coalesce(v.collection_id, k)
      destination_configs_normalized = [
        for dc in v.destination_configs : merge(dc, {
          params_normalized = (
            dc.params == null
            ? null
            : jsonencode(jsondecode(
              !startswith(trimspace(dc.params), "{")
              && !startswith(trimspace(dc.params), "[")
              ? (
                try(fileexists("${path.module}/${dc.params}"), false)
                ? file("${path.module}/${dc.params}")
                : (
                  try(fileexists(pathexpand(dc.params)), false)
                  ? file(pathexpand(dc.params))
                  : dc.params
                )
              )
              : dc.params
            ))
          )
        })
      ]
      entities_normalized = [
        for e in concat(
          v.entities,
          v.data_source == "outlook"
          && !contains([for x in v.entities : x.entity_name], "root")
          ? [{
            entity_name           = "root"
            key_property_mappings = tomap(null)
            params                = jsonencode({})
          }]
          : [],
          v.data_source == "sharepoint"
          && !contains([for x in v.entities : x.entity_name], "site")
          ? [{
            entity_name           = "site"
            key_property_mappings = tomap(null)
            params                = jsonencode({})
          }]
          : []
          ) : merge(e, {
            params_normalized = (
              e.params == null
              ? jsonencode({})
              : jsonencode(jsondecode(
                !startswith(trimspace(e.params), "{")
                && !startswith(trimspace(e.params), "[")
                ? (
                  try(fileexists("${path.module}/${e.params}"), false)
                  ? file("${path.module}/${e.params}")
                  : (
                    try(fileexists(pathexpand(e.params)), false)
                    ? file(pathexpand(e.params))
                    : e.params
                  )
                )
                : e.params
              ))
            )
        })
      ]
      json_params_normalized = (
        v.json_params == null
        ? null
        : jsonencode(jsondecode(
          !startswith(trimspace(v.json_params), "{")
          && !startswith(trimspace(v.json_params), "[")
          ? (
            try(fileexists("${path.module}/${v.json_params}"), false)
            ? file("${path.module}/${v.json_params}")
            : (
              try(fileexists(pathexpand(v.json_params)), false)
              ? file(pathexpand(v.json_params))
              : v.json_params
            )
          )
          : v.json_params
        ))
      )
    })
  }
  gemini_enterprise_data_stores = {
    for k, v in var.gemini_enterprise_data_stores : k => merge(v, {
      data_store_id = coalesce(v.data_store_id, k)
      json_schema_normalized = (
        v.json_schema == null
        ? null
        : jsonencode(jsondecode(
          !startswith(trimspace(v.json_schema), "{")
          && !startswith(trimspace(v.json_schema), "[")
          ? (
            try(fileexists("${path.module}/${v.json_schema}"), false)
            ? file("${path.module}/${v.json_schema}")
            : (
              try(fileexists(pathexpand(v.json_schema)), false)
              ? file(pathexpand(v.json_schema))
              : v.json_schema
            )
          )
          : v.json_schema
        ))
      )
    })
  }
  gemini_enterprise_data_stores_with_schema = {
    for k, v in local.gemini_enterprise_data_stores : k => v
    if v.json_schema != null
  }
  gemini_enterprise_mcp_data_connectors = merge([
    for service_id, s in var.agent_registry_services : {
      for app_id in toset(coalesce(s.agent_gateway_app_ids, [])) :
      "${service_id}/${app_id}" => merge(s, {
        app_id = app_id
        collection_id = (
          length(replace("${service_id}-${app_id}", "_", "-")) <= 54
          ? replace("${service_id}-${app_id}", "_", "-")
          : "${trimsuffix(substr(replace("${service_id}-${app_id}", "_", "-"), 0, 45), "-")}-${substr(md5(replace("${service_id}-${app_id}", "_", "-")), 0, 8)}"
        )
        oauth_config = try(coalesce(s.oauth_config, var.oauth_config), null)
        patch_body = jsonencode({
          actionConfig = {
            createBapConnection = true
            actionParams = merge(
              {
                auth_type                = try(coalesce(s.oauth_config, var.oauth_config), null) != null ? "OAUTH" : "NO_AUTH"
                instance_uri             = s.url
                mcp_server_source        = "BYO_MCP"
                use_agent_gateway_egress = try(local.gemini_enterprise_apps[app_id].has_egress_gateway, true)
              },
              !try(local.gemini_enterprise_apps[app_id].has_egress_gateway, true) ? {} : {
                agent_gateway_engine = "projects/${var.number}/locations/${var.location}/collections/${try(local.gemini_enterprise_apps[app_id].collection_id, "default_collection")}/engines/${try(local.gemini_enterprise_apps[app_id].engine_id, app_id)}"
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

resource "google_discovery_engine_data_store" "default" {
  for_each          = local.gemini_enterprise_data_stores
  project           = var.project_id
  location          = var.location
  data_store_id     = each.value.data_store_id
  display_name      = coalesce(each.value.display_name, each.value.data_store_id)
  industry_vertical = each.value.industry_vertical
  content_config    = each.value.content_config
  solution_types    = each.value.solution_types
  acl_enabled       = each.value.acl_enabled
  deletion_policy   = local.deletion_policy
  kms_key_name      = each.value.kms_key_name
  skip_default_schema_creation = coalesce(
    each.value.skip_default_schema_creation,
    each.value.json_schema != null
  )

  dynamic "document_processing_config" {
    for_each = each.value.document_processing_config == null ? [] : [""]

    content {
      dynamic "chunking_config" {
        for_each = (
          try(each.value.document_processing_config.chunking_config, null) == null
          ? [] : [""]
        )

        content {
          dynamic "layout_based_chunking_config" {
            for_each = (
              try(
                each.value.document_processing_config.chunking_config.layout_based_chunking_config,
                null
              ) == null
              ? [] : [""]
            )

            content {
              chunk_size = (
                each.value.document_processing_config.chunking_config.layout_based_chunking_config.chunk_size
              )
              include_ancestor_headings = (
                each.value.document_processing_config.chunking_config.layout_based_chunking_config.include_ancestor_headings
              )
            }
          }
        }
      }

      dynamic "default_parsing_config" {
        for_each = (
          try(each.value.document_processing_config.default_parsing_config, null) == null
          ? [] : [""]
        )

        content {
          dynamic "digital_parsing_config" {
            for_each = (
              try(
                each.value.document_processing_config.default_parsing_config.digital_parsing_config,
                null
              ) == true
              ? [""] : []
            )

            content {}
          }

          dynamic "layout_parsing_config" {
            for_each = (
              try(
                each.value.document_processing_config.default_parsing_config.layout_parsing_config,
                null
              ) == null
              ? []
              : [each.value.document_processing_config.default_parsing_config.layout_parsing_config]
            )

            content {
              enable_get_processed_document = layout_parsing_config.value.enable_get_processed_document
              enable_image_annotation       = layout_parsing_config.value.enable_image_annotation
              enable_llm_layout_parsing     = layout_parsing_config.value.enable_llm_layout_parsing
              enable_table_annotation       = layout_parsing_config.value.enable_table_annotation
              exclude_html_classes          = layout_parsing_config.value.exclude_html_classes
              exclude_html_elements         = layout_parsing_config.value.exclude_html_elements
              exclude_html_ids              = layout_parsing_config.value.exclude_html_ids
              structured_content_types      = layout_parsing_config.value.structured_content_types
            }
          }

          dynamic "ocr_parsing_config" {
            for_each = (
              try(
                each.value.document_processing_config.default_parsing_config.ocr_parsing_config,
                null
              ) == null
              ? [] : [""]
            )

            content {
              use_native_text = (
                each.value.document_processing_config.default_parsing_config.ocr_parsing_config.use_native_text
              )
            }
          }
        }
      }

      dynamic "parsing_config_overrides" {
        for_each = coalesce(
          each.value.document_processing_config.parsing_config_overrides, {}
        )

        content {
          file_type = parsing_config_overrides.key

          dynamic "digital_parsing_config" {
            for_each = (
              parsing_config_overrides.value.digital_parsing_config == true
              ? [""] : []
            )

            content {}
          }

          dynamic "layout_parsing_config" {
            for_each = (
              parsing_config_overrides.value.layout_parsing_config == null
              ? []
              : [parsing_config_overrides.value.layout_parsing_config]
            )

            content {
              enable_get_processed_document = layout_parsing_config.value.enable_get_processed_document
              enable_image_annotation       = layout_parsing_config.value.enable_image_annotation
              enable_llm_layout_parsing     = layout_parsing_config.value.enable_llm_layout_parsing
              enable_table_annotation       = layout_parsing_config.value.enable_table_annotation
              exclude_html_classes          = layout_parsing_config.value.exclude_html_classes
              exclude_html_elements         = layout_parsing_config.value.exclude_html_elements
              exclude_html_ids              = layout_parsing_config.value.exclude_html_ids
              structured_content_types      = layout_parsing_config.value.structured_content_types
            }
          }

          dynamic "ocr_parsing_config" {
            for_each = (
              parsing_config_overrides.value.ocr_parsing_config == null
              ? [] : [""]
            )

            content {
              use_native_text = parsing_config_overrides.value.ocr_parsing_config.use_native_text
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for app_id in each.value.app_ids :
        contains(keys(var.gemini_enterprise_apps), app_id)
      ])
      error_message = "Data store '${each.key}' references an app_id in app_ids that is not in var.gemini_enterprise_apps."
    }
  }

  depends_on = [
    google_discovery_engine_acl_config.default,
    google_discovery_engine_cmek_config.default,
    google_discovery_engine_user_store.default,
  ]

  # Discovery Engine rejects deleting a DataStore while it is still listed on
  # an Engine. Detach it from any referencing engine before destruction.
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    environment = {
      DATA_STORE_IDS  = jsonencode([self.data_store_id])
      DELETION_POLICY = coalesce(self.deletion_policy, "DELETE")
      LOCATION        = self.location
      PROJECT         = self.project
    }
    command = <<-EOT
      set -euo pipefail

      if [[ "$DELETION_POLICY" != "DELETE" ]]; then
        exit 0
      fi

      host_prefix=""
      [[ "$LOCATION" != "global" ]] && host_prefix="$${LOCATION}-"
      v1_ep="https://$${host_prefix}discoveryengine.googleapis.com/v1"
      v1alpha_ep="https://$${host_prefix}discoveryengine.googleapis.com/v1alpha"

      if [[ -n "$${GOOGLE_OAUTH_ACCESS_TOKEN:-}" ]]; then
        token="$GOOGLE_OAUTH_ACCESS_TOKEN"
      elif [[ -n "$${GOOGLE_IMPERSONATE_SERVICE_ACCOUNT:-}" ]]; then
        token="$(gcloud auth print-access-token --impersonate-service-account="$GOOGLE_IMPERSONATE_SERVICE_ACCOUNT")"
      else
        token="$(gcloud auth print-access-token 2>/dev/null || gcloud auth application-default print-access-token)"
      fi
      quota_project="$${GOOGLE_BILLING_PROJECT:-$${CLOUDSDK_BILLING_QUOTA_PROJECT:-$PROJECT}}"

      hdr=$(mktemp)
      body=$(mktemp)
      resp=$(mktemp)
      chmod 600 "$hdr"
      printf 'header = "Authorization: Bearer %s"\nheader = "X-Goog-User-Project: %s"\n' "$token" "$quota_project" > "$hdr"

      lockbase="/tmp/ge-ds-sync-$${PROJECT}-$${LOCATION}"
      if command -v flock >/dev/null 2>&1; then
        exec 9>"$${lockbase}.lock"
        flock -w 300 9
        cleanup() { rm -f "$hdr" "$body" "$resp"; }
      else
        lockdir="$${lockbase}.lockdir"
        waited=0
        while ! mkdir "$lockdir" 2>/dev/null; do
          if [[ -f "$lockdir/pid" ]]; then
            holder=$(cat "$lockdir/pid" 2>/dev/null || true)
            if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
              rm -rf "$lockdir"
              continue
            fi
          fi
          if (( waited >= 300 )); then
            echo "Timed out waiting for lock $lockdir" >&2
            exit 1
          fi
          sleep 1
          waited=$((waited + 1))
        done
        echo "$$" > "$lockdir/pid"
        cleanup() { rm -rf "$lockdir" "$hdr" "$body" "$resp"; }
      fi
      trap cleanup EXIT

      collections=("projects/$${PROJECT}/locations/$${LOCATION}/collections/default_collection")
      page_token=""
      while :; do
        col_url="$${v1alpha_ep}/projects/$${PROJECT}/locations/$${LOCATION}/collections"
        if [[ -n "$page_token" ]]; then
          col_url="$${col_url}?pageToken=$(jq -rn --arg t "$page_token" '$t | @uri')"
        fi
        status=$(curl -sS -K "$hdr" -o "$body" -w '%%{http_code}' "$col_url")
        [[ "$status" != 2* ]] && break
        while IFS= read -r col; do
          [[ -n "$col" && "$${col##*/}" != "default_collection" ]] && collections+=("$col")
        done < <(jq -r '.collections[]? | select(.dataConnector == null) | .name' "$body")
        page_token=$(jq -r '.nextPageToken // empty' "$body")
        [[ -z "$page_token" ]] && break
      done

      for col in "$${collections[@]}"; do
        page_token=""
        while :; do
          eng_url="$${v1_ep}/$${col}/engines"
          if [[ -n "$page_token" ]]; then
            eng_url="$${eng_url}?pageToken=$(jq -rn --arg t "$page_token" '$t | @uri')"
          fi
          status=$(curl -sS -K "$hdr" -o "$body" -w '%%{http_code}' "$eng_url")
          [[ "$status" == "404" ]] && break
          if [[ "$status" != 2* ]]; then
            echo "Failed to list Discovery Engine apps in $col (HTTP $status)" >&2
            cat "$body" >&2
            exit 1
          fi
          while IFS= read -r engine; do
            [[ -z "$engine" ]] && continue
            payload=$(jq -c --arg eng "$engine" --argjson targets "$DATA_STORE_IDS" \
              '.engines[] | select(.name == $eng) | ((.dataStoreIds // []) - $targets) as $rem | {dataStoreIds: (if ($rem | length) == 1 then [] else $rem end)}' "$body")
            patch_status=""
            for attempt in {1..5}; do
              patch_status=$(printf '%s' "$payload" | curl -sS -X PATCH -K "$hdr" \
                -H "Content-Type: application/json" \
                --data-binary @- \
                -o "$resp" -w '%%{http_code}' \
                "$${v1_ep}/$${engine}?updateMask=dataStoreIds")
              if [[ "$patch_status" == 2* || "$patch_status" == "404" ]]; then
                break
              fi
              if [[ "$patch_status" == 5* || "$patch_status" == "429" ]]; then
                sleep 2
                continue
              fi
              break
            done
            if [[ "$patch_status" != 2* && "$patch_status" != "404" ]]; then
              echo "Failed to detach stores from $engine (HTTP $patch_status)" >&2
              cat "$resp" >&2
              exit 1
            fi
          done < <(jq -r --argjson targets "$DATA_STORE_IDS" \
            '.engines[]? | select(any((.dataStoreIds // [])[]; . as $id | $targets | index($id))) | .name' "$body")
          page_token=$(jq -r '.nextPageToken // empty' "$body")
          [[ -z "$page_token" ]] && break
        done
      done
    EOT
  }
}

resource "google_discovery_engine_schema" "default" {
  for_each        = local.gemini_enterprise_data_stores_with_schema
  project         = var.project_id
  location        = google_discovery_engine_data_store.default[each.key].location
  data_store_id   = google_discovery_engine_data_store.default[each.key].data_store_id
  schema_id       = each.value.schema_id
  json_schema     = each.value.json_schema_normalized
  deletion_policy = local.deletion_policy
}

resource "google_discovery_engine_data_connector" "default" {
  for_each      = local.gemini_enterprise_data_connectors
  project       = var.project_id
  location      = var.location
  collection_id = each.value.collection_id
  collection_display_name = urlencode(
    coalesce(each.value.collection_display_name, each.value.collection_id)
  )
  data_source                  = each.value.data_source
  refresh_interval             = each.value.refresh_interval
  auto_run_disabled            = each.value.auto_run_disabled
  connector_modes              = each.value.connector_modes
  data_source_version          = each.value.data_source_version
  deletion_policy              = local.deletion_policy
  incremental_refresh_interval = each.value.incremental_refresh_interval
  incremental_sync_disabled    = each.value.incremental_sync_disabled
  json_params                  = each.value.json_params_normalized
  kms_key_name = try(
    coalesce(
      each.value.kms_key_name,
      try(
        var.gemini_enterprise_encryption_config.set_default
        ? var.gemini_enterprise_encryption_config.kms_key
        : null,
        null
      )
    ),
    null
  )
  params = (
    each.value.json_params_normalized == null
    ? coalesce(each.value.params, {})
    : null
  )
  static_ip_enabled = each.value.static_ip_enabled
  sync_mode         = each.value.sync_mode
  tag               = coalesce(each.value.tag, replace(each.value.collection_id, "_", "-"))

  dynamic "action_config" {
    for_each = each.value.action_config != null ? [each.value.action_config] : []
    content {
      action_params         = action_config.value.action_params
      create_bap_connection = action_config.value.create_bap_connection
    }
  }

  dynamic "bap_config" {
    for_each = each.value.bap_config != null ? [each.value.bap_config] : []
    content {
      enabled_actions           = bap_config.value.enabled_actions
      supported_connector_modes = bap_config.value.supported_connector_modes
    }
  }

  dynamic "destination_configs" {
    for_each = each.value.destination_configs_normalized
    content {
      key    = destination_configs.value.key
      params = destination_configs.value.params_normalized
      dynamic "destinations" {
        for_each = coalesce(destination_configs.value.destinations, [])
        content {
          host = destinations.value.host
          port = destinations.value.port
        }
      }
    }
  }

  dynamic "entities" {
    for_each = each.value.entities_normalized
    content {
      entity_name           = entities.value.entity_name
      key_property_mappings = entities.value.key_property_mappings
      params                = entities.value.params_normalized
    }
  }

  dynamic "metadata" {
    for_each = each.value.metadata != null ? [each.value.metadata] : []
    content {
      author            = metadata.value.author
      description       = metadata.value.description
      note              = metadata.value.note
      short_description = metadata.value.short_description
      title             = metadata.value.title
    }
  }

  depends_on = [
    google_discovery_engine_acl_config.default,
    google_discovery_engine_cmek_config.default,
    google_discovery_engine_user_store.default,
  ]

  lifecycle {
    # The Discovery Engine GET dataConnector API does not return
    # collectionDisplayName on import, and the provider marks it ForceNew.
    ignore_changes = [
      collection_display_name,
    ]

    precondition {
      condition = alltrue([
        for app_id in each.value.app_ids :
        contains(keys(var.gemini_enterprise_apps), app_id)
      ])
      error_message = "Data connector '${each.key}' references an app_id in app_ids that is not in var.gemini_enterprise_apps."
    }
  }

  # Terraform destroys removed data_connector instances before updating
  # google_discovery_engine_search_engine in-place, and the Discovery Engine
  # API rejects deleting a DataConnector while any of its entity data stores
  # are still listed on an Engine. Detach them first.
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    environment = {
      DATA_STORE_IDS = jsonencode([
        for e in self.entities :
        try(e.data_store, null) != null && try(e.data_store, "") != ""
        ? basename(e.data_store)
        : "${self.collection_id}_${e.entity_name}"
      ])
      DELETION_POLICY = coalesce(self.deletion_policy, "DELETE")
      LOCATION        = self.location
      PROJECT         = self.project
    }
    command = <<-EOT
      set -euo pipefail

      if [[ "$DELETION_POLICY" != "DELETE" ]]; then
        exit 0
      fi

      host_prefix=""
      [[ "$LOCATION" != "global" ]] && host_prefix="$${LOCATION}-"
      v1_ep="https://$${host_prefix}discoveryengine.googleapis.com/v1"
      v1alpha_ep="https://$${host_prefix}discoveryengine.googleapis.com/v1alpha"

      if [[ -n "$${GOOGLE_OAUTH_ACCESS_TOKEN:-}" ]]; then
        token="$GOOGLE_OAUTH_ACCESS_TOKEN"
      elif [[ -n "$${GOOGLE_IMPERSONATE_SERVICE_ACCOUNT:-}" ]]; then
        token="$(gcloud auth print-access-token --impersonate-service-account="$GOOGLE_IMPERSONATE_SERVICE_ACCOUNT")"
      else
        token="$(gcloud auth print-access-token 2>/dev/null || gcloud auth application-default print-access-token)"
      fi
      quota_project="$${GOOGLE_BILLING_PROJECT:-$${CLOUDSDK_BILLING_QUOTA_PROJECT:-$PROJECT}}"

      hdr=$(mktemp)
      body=$(mktemp)
      resp=$(mktemp)
      chmod 600 "$hdr"
      printf 'header = "Authorization: Bearer %s"\nheader = "X-Goog-User-Project: %s"\n' "$token" "$quota_project" > "$hdr"

      lockbase="/tmp/ge-ds-sync-$${PROJECT}-$${LOCATION}"
      if command -v flock >/dev/null 2>&1; then
        exec 9>"$${lockbase}.lock"
        flock -w 300 9
        cleanup() { rm -f "$hdr" "$body" "$resp"; }
      else
        lockdir="$${lockbase}.lockdir"
        waited=0
        while ! mkdir "$lockdir" 2>/dev/null; do
          if [[ -f "$lockdir/pid" ]]; then
            holder=$(cat "$lockdir/pid" 2>/dev/null || true)
            if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
              rm -rf "$lockdir"
              continue
            fi
          fi
          if (( waited >= 300 )); then
            echo "Timed out waiting for lock $lockdir" >&2
            exit 1
          fi
          sleep 1
          waited=$((waited + 1))
        done
        echo "$$" > "$lockdir/pid"
        cleanup() { rm -rf "$lockdir" "$hdr" "$body" "$resp"; }
      fi
      trap cleanup EXIT

      collections=("projects/$${PROJECT}/locations/$${LOCATION}/collections/default_collection")
      page_token=""
      while :; do
        col_url="$${v1alpha_ep}/projects/$${PROJECT}/locations/$${LOCATION}/collections"
        if [[ -n "$page_token" ]]; then
          col_url="$${col_url}?pageToken=$(jq -rn --arg t "$page_token" '$t | @uri')"
        fi
        status=$(curl -sS -K "$hdr" -o "$body" -w '%%{http_code}' "$col_url")
        [[ "$status" != 2* ]] && break
        while IFS= read -r col; do
          [[ -n "$col" && "$${col##*/}" != "default_collection" ]] && collections+=("$col")
        done < <(jq -r '.collections[]? | select(.dataConnector == null) | .name' "$body")
        page_token=$(jq -r '.nextPageToken // empty' "$body")
        [[ -z "$page_token" ]] && break
      done

      for col in "$${collections[@]}"; do
        page_token=""
        while :; do
          eng_url="$${v1_ep}/$${col}/engines"
          if [[ -n "$page_token" ]]; then
            eng_url="$${eng_url}?pageToken=$(jq -rn --arg t "$page_token" '$t | @uri')"
          fi
          status=$(curl -sS -K "$hdr" -o "$body" -w '%%{http_code}' "$eng_url")
          [[ "$status" == "404" ]] && break
          if [[ "$status" != 2* ]]; then
            echo "Failed to list Discovery Engine apps in $col (HTTP $status)" >&2
            cat "$body" >&2
            exit 1
          fi
          while IFS= read -r engine; do
            [[ -z "$engine" ]] && continue
            payload=$(jq -c --arg eng "$engine" --argjson targets "$DATA_STORE_IDS" \
              '.engines[] | select(.name == $eng) | ((.dataStoreIds // []) - $targets) as $rem | {dataStoreIds: (if ($rem | length) == 1 then [] else $rem end)}' "$body")
            patch_status=""
            for attempt in {1..5}; do
              patch_status=$(printf '%s' "$payload" | curl -sS -X PATCH -K "$hdr" \
                -H "Content-Type: application/json" \
                --data-binary @- \
                -o "$resp" -w '%%{http_code}' \
                "$${v1_ep}/$${engine}?updateMask=dataStoreIds")
              if [[ "$patch_status" == 2* || "$patch_status" == "404" ]]; then
                break
              fi
              if [[ "$patch_status" == 5* || "$patch_status" == "429" ]]; then
                sleep 2
                continue
              fi
              break
            done
            if [[ "$patch_status" != 2* && "$patch_status" != "404" ]]; then
              echo "Failed to detach stores from $engine (HTTP $patch_status)" >&2
              cat "$resp" >&2
              exit 1
            fi
          done < <(jq -r --argjson targets "$DATA_STORE_IDS" \
            '.engines[]? | select(any((.dataStoreIds // [])[]; . as $id | $targets | index($id))) | .name' "$body")
          page_token=$(jq -r '.nextPageToken // empty' "$body")
          [[ -z "$page_token" ]] && break
        done
      done
    EOT
  }
}

resource "google_discovery_engine_data_connector" "mcp" {
  for_each                = local.gemini_enterprise_mcp_data_connectors
  project                 = var.project_id
  location                = var.location
  collection_id           = each.value.collection_id
  collection_display_name = urlencode(coalesce(each.value.display_name, each.value.service_id))
  data_source             = "custom_mcp"
  connector_modes         = ["FEDERATED"]
  kms_key_name = try(
    var.gemini_enterprise_encryption_config.set_default
    ? var.gemini_enterprise_encryption_config.kms_key
    : null,
    null
  )
  refresh_interval  = "86400s"
  static_ip_enabled = false
  tag               = replace(each.value.collection_id, "_", "-")
  deletion_policy   = local.deletion_policy

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

  depends_on = [
    google_discovery_engine_acl_config.default,
    google_discovery_engine_cmek_config.default,
    google_discovery_engine_user_store.default,
  ]

  lifecycle {
    ignore_changes = [
      action_config,
      collection_display_name,
      params,
    ]

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
    environment = {
      DATA_STORE_IDS  = jsonencode(["${self.collection_id}_mcp_data"])
      DELETION_POLICY = coalesce(self.deletion_policy, "DELETE")
      LOCATION        = self.location
      PROJECT         = self.project
    }
    command = <<-EOT
      set -euo pipefail

      if [[ "$DELETION_POLICY" != "DELETE" ]]; then
        exit 0
      fi

      host_prefix=""
      [[ "$LOCATION" != "global" ]] && host_prefix="$${LOCATION}-"
      v1_ep="https://$${host_prefix}discoveryengine.googleapis.com/v1"
      v1alpha_ep="https://$${host_prefix}discoveryengine.googleapis.com/v1alpha"

      if [[ -n "$${GOOGLE_OAUTH_ACCESS_TOKEN:-}" ]]; then
        token="$GOOGLE_OAUTH_ACCESS_TOKEN"
      elif [[ -n "$${GOOGLE_IMPERSONATE_SERVICE_ACCOUNT:-}" ]]; then
        token="$(gcloud auth print-access-token --impersonate-service-account="$GOOGLE_IMPERSONATE_SERVICE_ACCOUNT")"
      else
        token="$(gcloud auth print-access-token 2>/dev/null || gcloud auth application-default print-access-token)"
      fi
      quota_project="$${GOOGLE_BILLING_PROJECT:-$${CLOUDSDK_BILLING_QUOTA_PROJECT:-$PROJECT}}"

      hdr=$(mktemp)
      body=$(mktemp)
      resp=$(mktemp)
      chmod 600 "$hdr"
      printf 'header = "Authorization: Bearer %s"\nheader = "X-Goog-User-Project: %s"\n' "$token" "$quota_project" > "$hdr"

      lockbase="/tmp/ge-ds-sync-$${PROJECT}-$${LOCATION}"
      if command -v flock >/dev/null 2>&1; then
        exec 9>"$${lockbase}.lock"
        flock -w 300 9
        cleanup() { rm -f "$hdr" "$body" "$resp"; }
      else
        lockdir="$${lockbase}.lockdir"
        waited=0
        while ! mkdir "$lockdir" 2>/dev/null; do
          if [[ -f "$lockdir/pid" ]]; then
            holder=$(cat "$lockdir/pid" 2>/dev/null || true)
            if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
              rm -rf "$lockdir"
              continue
            fi
          fi
          if (( waited >= 300 )); then
            echo "Timed out waiting for lock $lockdir" >&2
            exit 1
          fi
          sleep 1
          waited=$((waited + 1))
        done
        echo "$$" > "$lockdir/pid"
        cleanup() { rm -rf "$lockdir" "$hdr" "$body" "$resp"; }
      fi
      trap cleanup EXIT

      collections=("projects/$${PROJECT}/locations/$${LOCATION}/collections/default_collection")
      page_token=""
      while :; do
        col_url="$${v1alpha_ep}/projects/$${PROJECT}/locations/$${LOCATION}/collections"
        if [[ -n "$page_token" ]]; then
          col_url="$${col_url}?pageToken=$(jq -rn --arg t "$page_token" '$t | @uri')"
        fi
        status=$(curl -sS -K "$hdr" -o "$body" -w '%%{http_code}' "$col_url")
        [[ "$status" != 2* ]] && break
        while IFS= read -r col; do
          [[ -n "$col" && "$${col##*/}" != "default_collection" ]] && collections+=("$col")
        done < <(jq -r '.collections[]? | select(.dataConnector == null) | .name' "$body")
        page_token=$(jq -r '.nextPageToken // empty' "$body")
        [[ -z "$page_token" ]] && break
      done

      for col in "$${collections[@]}"; do
        page_token=""
        while :; do
          eng_url="$${v1_ep}/$${col}/engines"
          if [[ -n "$page_token" ]]; then
            eng_url="$${eng_url}?pageToken=$(jq -rn --arg t "$page_token" '$t | @uri')"
          fi
          status=$(curl -sS -K "$hdr" -o "$body" -w '%%{http_code}' "$eng_url")
          [[ "$status" == "404" ]] && break
          if [[ "$status" != 2* ]]; then
            echo "Failed to list Discovery Engine apps in $col (HTTP $status)" >&2
            cat "$body" >&2
            exit 1
          fi
          while IFS= read -r engine; do
            [[ -z "$engine" ]] && continue
            payload=$(jq -c --arg eng "$engine" --argjson targets "$DATA_STORE_IDS" \
              '.engines[] | select(.name == $eng) | ((.dataStoreIds // []) - $targets) as $rem | {dataStoreIds: (if ($rem | length) == 1 then [] else $rem end)}' "$body")
            patch_status=""
            for attempt in {1..5}; do
              patch_status=$(printf '%s' "$payload" | curl -sS -X PATCH -K "$hdr" \
                -H "Content-Type: application/json" \
                --data-binary @- \
                -o "$resp" -w '%%{http_code}' \
                "$${v1_ep}/$${engine}?updateMask=dataStoreIds")
              if [[ "$patch_status" == 2* || "$patch_status" == "404" ]]; then
                break
              fi
              if [[ "$patch_status" == 5* || "$patch_status" == "429" ]]; then
                sleep 2
                continue
              fi
              break
            done
            if [[ "$patch_status" != 2* && "$patch_status" != "404" ]]; then
              echo "Failed to detach stores from $engine (HTTP $patch_status)" >&2
              cat "$resp" >&2
              exit 1
            fi
          done < <(jq -r --argjson targets "$DATA_STORE_IDS" \
            '.engines[]? | select(any((.dataStoreIds // [])[]; . as $id | $targets | index($id))) | .name' "$body")
          page_token=$(jq -r '.nextPageToken // empty' "$body")
          [[ -z "$page_token" ]] && break
        done
      done
    EOT
  }
}

# google_discovery_engine_data_connector types action_config.action_params as
# map(string), so it serializes boolean parameters as strings, which the
# Discovery Engine API ignores. Patch actionConfig via local-exec so booleans
# and OAuth/gateway settings are always reconciled.
resource "terraform_data" "mcp_agent_gateway_patch" {
  for_each = local.gemini_enterprise_mcp_data_connectors

  triggers_replace = {
    connector  = google_discovery_engine_data_connector.mcp[each.key].name
    patch_body = nonsensitive(sha256(each.value.patch_body))
  }

  provisioner "local-exec" {
    quiet       = true
    interpreter = ["/bin/bash", "-c"]
    environment = {
      CONNECTOR_KEY  = each.key
      CONNECTOR_NAME = google_discovery_engine_data_connector.mcp[each.key].name
      LOCATION       = var.location
      PATCH_BODY     = each.value.patch_body
      PROJECT        = var.project_id
    }
    command = <<-EOT
      set -euo pipefail

      host_prefix=""
      [[ "$LOCATION" != "global" ]] && host_prefix="$${LOCATION}-"
      endpoint="https://$${host_prefix}discoveryengine.googleapis.com/v1"
      url="$${endpoint}/$${CONNECTOR_NAME}"

      if [[ -n "$${GOOGLE_OAUTH_ACCESS_TOKEN:-}" ]]; then
        token="$GOOGLE_OAUTH_ACCESS_TOKEN"
      elif [[ -n "$${GOOGLE_IMPERSONATE_SERVICE_ACCOUNT:-}" ]]; then
        token="$(gcloud auth print-access-token --impersonate-service-account="$GOOGLE_IMPERSONATE_SERVICE_ACCOUNT")"
      else
        token="$(gcloud auth print-access-token 2>/dev/null || gcloud auth application-default print-access-token)"
      fi
      quota_project="$${GOOGLE_BILLING_PROJECT:-$${CLOUDSDK_BILLING_QUOTA_PROJECT:-$PROJECT}}"

      hdr=$(mktemp)
      body=$(mktemp)
      chmod 600 "$hdr"
      printf 'header = "Authorization: Bearer %s"\nheader = "X-Goog-User-Project: %s"\n' "$token" "$quota_project" > "$hdr"
      trap 'rm -f "$hdr" "$body"' EXIT

      for attempt in {1..12}; do
        status=$(printf '%s' "$PATCH_BODY" | curl -sS -X PATCH -K "$hdr" \
          -H "Content-Type: application/json" \
          --data-binary @- \
          -o "$body" -w '%%{http_code}' \
          "$${url}?updateMask=actionConfig")

        if [[ "$status" == 2* ]]; then
          exit 0
        fi
        if [[ "$status" == "400" ]] && grep -q "INITIALIZING" "$body"; then
          sleep 5
          continue
        fi
        break
      done

      echo "MCP data connector actionConfig patch failed for $CONNECTOR_KEY (HTTP $status)" >&2
      cat "$body" >&2
      exit 1
    EOT
  }

  depends_on = [
    terraform_data.app_agent_gateway_patch,
  ]
}
