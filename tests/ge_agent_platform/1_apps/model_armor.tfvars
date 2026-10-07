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
    model_armor_config = {
      authz_hosts = ["api.example.com"]
      enable      = true
    }
    networking = {
      access_types = ["PRIVATE", "PUBLIC"]
      dns_peering_config = {
        domain = "corp.example.com."
      }
      vpc_egress = "PRIVATE_RANGES_ONLY"
    }
  }
}

model_armor_floor_setting = {
  enabled = true
}
