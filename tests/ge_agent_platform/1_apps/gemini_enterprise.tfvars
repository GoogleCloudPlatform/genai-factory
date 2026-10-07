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

gemini_enterprise_apps = {
  ge-app-main = {
    assistant = {
      banned_phrases = [
        {
          phrase            = "competitor-secret"
          match_type        = "SIMPLE_STRING_MATCH"
          ignore_diacritics = true
        }
      ]
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
    }
    iam = {
      "roles/discoveryengine.agentspaceUser" = [
        "group:employees@example.com"
      ]
    }
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
    iam = {
      "roles/iap.egressor" = [
        "principal://goog/subject/user@example.com"
      ]
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
