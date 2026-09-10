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

region = "europe-west1"

networking_config = {
  subnet = "projects/test-gf-geap-hp-0/regions/europe-west1/subnetworks/sub-0"
  vpc    = "projects/test-gf-geap-hp-0/global/networks/net-0"
}

agent_gateway_config = {
  egress = {
    iap = {
      iam_enforcement_mode = "DRY_RUN"
    }
    registry_locations = ["eu", "regional"]
  }
}

agent_registry_services = {
  test-agent = {
    display_name = "Test Agent"
    url          = "https://agent.example.com"
    type         = "agent"
    content      = "{}"
    iam = {
      "roles/iap.egressor" = ["principal://goog/subject/user@example.com"]
    }
  }
  test-endpoint = {
    display_name = "Test Endpoint"
    url          = "https://endpoint.example.com"
    iam_bindings = {
      forecast-tool-only = {
        members = ["principal://goog/subject/user@example.com"]
        role    = "roles/iap.egressor"
        condition = {
          title      = "forecast-tool-only"
          expression = "api.getAttribute('iap.googleapis.com/mcp.toolName', '') in ['get_forecast', '']"
        }
      }
    }
  }
  test-mcp = {
    display_name = "Test MCP Server"
    url          = "https://mcp.example.com"
    type         = "mcp_server"
    content      = "{}"
    iam_bindings_additive = {
      single-agent = {
        member = "principal://goog/subject/user@example.com"
        role   = "roles/iap.egressor"
      }
    }
  }
}

agent_registry_iam = {
  "roles/iap.egressor" = ["principal://goog/subject/registry@example.com"]
}

agent_registry_iam_by_principals = {
  "principalSet://goog/group/agents@example.com" = ["roles/iap.egressor"]
}

agent_registry_iam_bindings = {
  external-mcp = {
    members       = ["principal://goog/subject/user@example.com"]
    role          = "roles/iap.egressor"
    mcp_server_id = "external-mcp"
  }
}

agent_registry_iam_bindings_additive = {
  external-endpoint = {
    member      = "principal://goog/subject/user@example.com"
    role        = "roles/iap.egressor"
    endpoint_id = "external-endpoint"
  }
  registry-wide = {
    member = "principal://goog/subject/other@example.com"
    role   = "roles/iap.egressor"
  }
}
