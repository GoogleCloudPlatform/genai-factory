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
    registry_locations = ["eu"]
  }
}

agent_registry_services = {
  test-agent = {
    display_name = "Test Agent"
    type         = "agent"
    content      = "{}"
    access_policy_rules = {
      allow-user = {
        description = "Allow user to call test-agent"
        principals  = ["user:user@example.com"]
      }
    }
  }
  test-endpoint = {
    display_name = "Test Endpoint"
    url          = "https://endpoint.example.com"
    access_policy_rules = {
      allow-user = {
        description = "Allow user to call test-endpoint"
        principals  = ["principal://goog/subject/user@example.com"]
      }
    }
  }
  test-mcp = {
    display_name = "Test MCP Server"
    url          = "https://mcp.example.com"
    type         = "mcp_server"
    content      = "{}"
    access_policy_rules = {
      readonly-tools = {
        description = "Allow read-only tools on test-mcp"
        principals  = ["principal://goog/subject/user@example.com"]
        condition   = "destination.agent_registry.mcp_server.tool.annotations.read_only_hint == true"
      }
    }
  }
}

access_policies = {
  agw-geap = {
    display_name = "GEAP Egress Access Policy"
    rules = {
      registry-wide = {
        description = "Allow registry-wide egress"
        principals  = ["principal://goog/subject/registry@example.com"]
        registry    = true
      }
      external-mcp = {
        description   = "Allow calling external-mcp"
        principals    = ["principal://goog/subject/user@example.com"]
        mcp_server_id = "external-mcp"
      }
      external-endpoint = {
        description = "Allow calling external-endpoint"
        principals  = ["principal://goog/subject/user@example.com"]
        endpoint_id = "external-endpoint"
      }
      unregistered-ocr = {
        description = "Allow POST to external OCR API"
        principals  = ["group:agents@example.com"]
        condition   = "destination.unregistered.host == 'ocr.example.com' && destination.unregistered.method == 'POST'"
      }
    }
  }
}
