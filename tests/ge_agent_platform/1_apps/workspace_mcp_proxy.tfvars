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

region   = "us-central1"
location = "us"

networking_config = {
  subnet = "projects/test-gf-geap-hp-0/regions/us-central1/subnetworks/sub-0"
  vpc    = "projects/test-gf-geap-hp-0/global/networks/net-0"
}

gemini_enterprise_iam = {
  idp_type            = "THIRD_PARTY"
  workforce_pool_name = "locations/global/workforcePools/corp-sso-pool"
}

model_armor_floor_setting = {
  enabled          = true
  enforcement_type = "INSPECT_AND_BLOCK"
  logging          = true
}

gemini_enterprise_apps = {
  ge-app-prod = {
    assistant = {
      model_armor = {
        enable = true
      }
      web_grounding_type = "WEB_GROUNDING_TYPE_DISABLED"
    }
    engine = {
      display_name               = "Gemini Enterprise Production"
      required_subscription_tier = "SUBSCRIPTION_TIER_SEARCH_AND_ASSISTANT"
      search_add_ons             = ["SEARCH_ADD_ON_LLM"]
      search_tier                = "SEARCH_TIER_ENTERPRISE"
      features = {
        agent-gallery                        = "FEATURE_STATE_ON"
        agent-sharing-without-admin-approval = "FEATURE_STATE_OFF"
        enable-end-user-sharing-with-groups  = "FEATURE_STATE_OFF"
        model-selector                       = "FEATURE_STATE_ON"
        workflow-agents                      = "FEATURE_STATE_ON"
      }
      knowledge_graph = {
        enable_private_knowledge_graph = true
      }
    }
    iam = {
      "roles/discoveryengine.agentspaceUser" = [
        "group:workforce@example.com"
      ]
    }
  }
  ge-app-validation = {
    assistant = {
      model_armor = {
        enable = true
      }
      web_grounding_type = "WEB_GROUNDING_TYPE_DISABLED"
    }
    engine = {
      display_name               = "Gemini Enterprise Validation"
      required_subscription_tier = "SUBSCRIPTION_TIER_SEARCH_AND_ASSISTANT"
      search_add_ons             = ["SEARCH_ADD_ON_LLM"]
      search_tier                = "SEARCH_TIER_ENTERPRISE"
    }
    iam = {
      "roles/discoveryengine.agentspaceUser" = [
        "group:ai-security-validators@example.com"
      ]
    }
  }
}

# Native Google Workspace connectors locked strictly to FEDERATED (read-only
# search) mode; mutative actions are disabled so all outbound email/calendar
# writes flow exclusively through workspace_mcp_proxy_config.
gemini_enterprise_data_connectors = {
  google-drive = {
    app_ids                 = ["ge-app-prod", "ge-app-validation"]
    auto_run_disabled       = true
    collection_display_name = "Google Drive (Read-Only Federated)"
    connector_modes         = ["FEDERATED"]
    data_source             = "google_drive"
    entities                = [{ entity_name = "google_drive" }]
    json_params             = "{}"
    kms_key_name            = "projects/test-gf-geap-0/locations/us/keyRings/ge-ring/cryptoKeys/ge-key"
    refresh_interval        = "0s"
  }
  google-mail = {
    app_ids                 = ["ge-app-prod", "ge-app-validation"]
    auto_run_disabled       = true
    collection_display_name = "Gmail (Read-Only Federated)"
    connector_modes         = ["FEDERATED"]
    data_source             = "google_mail"
    entities                = [{ entity_name = "google_mail" }]
    json_params             = "{}"
    kms_key_name            = "projects/test-gf-geap-0/locations/us/keyRings/ge-ring/cryptoKeys/ge-key"
    refresh_interval        = "0s"
  }
  google-calendar = {
    app_ids                 = ["ge-app-prod", "ge-app-validation"]
    auto_run_disabled       = true
    collection_display_name = "Google Calendar (Read-Only Federated)"
    connector_modes         = ["FEDERATED"]
    data_source             = "google_calendar"
    entities                = [{ entity_name = "google_calendar" }]
    json_params             = "{}"
    kms_key_name            = "projects/test-gf-geap-0/locations/us/keyRings/ge-ring/cryptoKeys/ge-key"
    refresh_interval        = "0s"
  }
}

workspace_mcp_proxy_config = {
  enable                     = true
  allowed_domains            = ["example.com"]
  app_ids                    = ["ge-app-prod", "ge-app-validation"]
  automated_send_self_only   = true
  enable_automated_send_tool = false
  access_principals = [
    "principal://goog/subject/user@example.com"
  ]
  oauth_config = {
    auth_uri        = "https://accounts.google.com/o/oauth2/v2/auth"
    auth_uri_params = "&access_type=offline&prompt=consent"
    client_id       = "projects/test-gf-geap-0/secrets/ws-oauth-client-id/versions/1"
    client_secret   = "projects/test-gf-geap-0/secrets/ws-oauth-client-secret/versions/1"
    scopes = [
      "https://www.googleapis.com/auth/gmail.send",
      "https://www.googleapis.com/auth/gmail.compose",
      "https://www.googleapis.com/auth/calendar.events",
    ]
    token_uri = "https://oauth2.googleapis.com/token"
  }
}
