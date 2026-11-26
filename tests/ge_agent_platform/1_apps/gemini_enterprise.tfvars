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

name = "agw-geap"

project_id = "test-gf-geap-0"
number     = "1234567890"

region   = "europe-west1"
location = "eu"

networking_config = {
  subnet = "projects/test-gf-geap-hp-0/regions/europe-west1/subnetworks/sub-0"
  vpc    = "projects/test-gf-geap-hp-0/global/networks/net-0"
}

gemini_enterprise_antigravity_principals = [
  "group:developers@example.com"
]

gemini_enterprise_encryption_config = {
  kms_key = "projects/test-gf-geap-0/locations/europe/keyRings/ge/cryptoKeys/default"
  single_region_keys = [
    "projects/test-gf-geap-0/locations/europe-west1/keyRings/ge-ew1/cryptoKeys/default",
    "projects/test-gf-geap-0/locations/europe-west4/keyRings/ge-ew4/cryptoKeys/default",
    "projects/test-gf-geap-0/locations/europe-north1/keyRings/ge-en1/cryptoKeys/default",
  ]
}

gemini_enterprise_iam = {
  idp_type = "GSUITE"
}

gemini_enterprise_user_store_config = {
  default_license_config             = "projects/test-gf-geap-0/locations/eu/licenseConfigs/default"
  enable_expired_license_auto_update = true
  enable_license_auto_register       = true
}

gemini_enterprise_data_stores = {
  kb-docs = {
    app_ids        = ["ge-app-main"]
    content_config = "CONTENT_REQUIRED"
    display_name   = "Knowledge Base Docs"
    document_processing_config = {
      chunking_config = {
        layout_based_chunking_config = {
          chunk_size                = 500
          include_ancestor_headings = true
        }
      }
      default_parsing_config = {
        digital_parsing_config = true
      }
      parsing_config_overrides = {
        pdf = {
          ocr_parsing_config = {
            use_native_text = true
          }
        }
      }
    }
  }
  kb-structured = {
    app_ids        = ["ge-app-single"]
    content_config = "NO_CONTENT"
    display_name   = "Structured Catalog"
    json_schema    = "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\"}}}"
  }
}

gemini_enterprise_apps = {
  ge-app-main = {
    assistant = {
      banned_phrases = {
        competitor-secret = {
          match_type        = "SIMPLE_STRING_MATCH"
          ignore_diacritics = true
        }
      }
      default_web_grounding_toggle_off = true
      generation_config = {
        default_language   = "en"
        system_instruction = "You are a helpful enterprise assistant."
      }
      model_armor = {
        enable = true
      }
      web_grounding_type = "WEB_GROUNDING_TYPE_DISABLED"
    }
    engine = {
      display_name               = "Gemini Enterprise Main"
      disable_analytics          = false
      search_tier                = "SEARCH_TIER_ENTERPRISE"
      required_subscription_tier = "SUBSCRIPTION_TIER_SEARCH_AND_ASSISTANT"
      search_add_ons = [
        "SEARCH_ADD_ON_LLM"
      ]
      features = {
        agent-gallery  = "FEATURE_STATE_ON"
        model-selector = "FEATURE_STATE_ON"
      }
      procurement_contact_emails = ["platform@example.com"]
    }
    iam = {
      "roles/discoveryengine.agentspaceUser" = [
        "group:employees@example.com"
      ]
    }
    iam_by_principals = {
      "group:admins@example.com" = [
        "roles/discoveryengine.agentspaceUser"
      ]
    }
    iam_bindings_additive = {
      contractor-access = {
        member = "user:contractor@example.com"
        role   = "roles/discoveryengine.viewer"
      }
    }
    widget_config = {
      access_settings = {
        enable_web_app = true
        language_code  = "en"
      }
      ui_settings = {
        enable_autocomplete     = true
        interaction_type        = "SEARCH_WITH_ANSWER"
        result_description_type = "SNIPPET"
        data_store_ui_configs = {
          kb-docs = {
            facet_fields = {
              category = "Category"
            }
          }
        }
      }
    }
  }
  ge-app-single = {
    egress_agent_gateway = ""
    engine = {
      display_name = "Single Store App"
    }
  }
  ge-app-adopted = {
    data_store_ids = ["kb-docs"]
    iam_bindings = {
      adopted-users = {
        members = ["group:adopted@example.com"]
        role    = "roles/discoveryengine.agentspaceUser"
      }
    }
  }
}

gemini_enterprise_data_connectors = {
  confluence = {
    data_source             = "confluence"
    app_ids                 = ["ge-app-main"]
    collection_display_name = "Confluence Cloud"
    connector_modes         = ["DATA_INGESTION"]
    entities = [
      { entity_name = "page" },
      { entity_name = "space" },
    ]
    params = {
      api_token    = "projects/test-gf-geap-0/secrets/confluence-token/versions/1"
      auth_type    = "BASIC_AUTH"
      instance_uri = "https://example.atlassian.net"
      user_account = "admin@example.com"
    }
    refresh_interval = "86400s"
    sync_mode        = "PERIODIC"
  }
  onedrive = {
    data_source             = "onedrive"
    action_config           = { create_bap_connection = false }
    app_ids                 = ["ge-app-main"]
    bap_config              = { supported_connector_modes = ["ACTIONS"] }
    collection_display_name = "OneDrive"
    connector_modes         = ["FEDERATED"]
    destination_configs = [
      {
        key = "url"
        destinations = [
          { host = "https://example-my.sharepoint.com/" },
        ]
      },
    ]
    entities = [
      {
        entity_name = "file"
        params      = "{\"exclusion_filters\":{},\"inclusion_filters\":{}}"
      },
    ]
    refresh_interval = "86400s"
  }
}

agent_registry_services = {
  weather-mcp = {
    display_name          = "Weather MCP Server"
    url                   = "https://weather-mcp.example.com/mcp"
    type                  = "mcp_server"
    protocol              = "JSONRPC"
    content               = "{}"
    agent_gateway_app_ids = ["ge-app-main"]
    access_policy_rules = {
      allow-user = {
        description = "Allow user to call weather-mcp"
        principals = [
          "principal://goog/subject/user@example.com"
        ]
      }
    }
  }
}

oauth_config = {
  auth_uri        = "https://accounts.google.com/o/oauth2/v2/auth"
  auth_uri_params = "&access_type=offline&prompt=consent"
  client_id       = "projects/test-gf-geap-0/secrets/mcp-oauth-client-id/versions/1"
  client_secret   = "projects/test-gf-geap-0/secrets/mcp-oauth-client-secret/versions/1"
  scopes          = ["openid", "email", "profile"]
  token_uri       = "https://oauth2.googleapis.com/token"
}
