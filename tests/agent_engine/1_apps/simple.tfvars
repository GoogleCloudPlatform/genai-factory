# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

name   = "test-agent"
prefix = "test"

project_id            = "test-project"
number                = "123456789"
region                = "europe-west1"
network_attachment_id = "projects/test-project/regions/europe-west1/networkAttachments/test-attachment"
proxy_ip              = "10.0.0.100"

networking_config = {
  subnet = "test-subnet"
  vpc    = "test-vpc"
}

subnet_self_links = {
  "test-subnet" = "projects/test-project/regions/europe-west1/subnetworks/test-subnet"
}

vpc_self_links = {
  "test-vpc" = "projects/test-project/global/networks/test-vpc"
}

service_account_emails = {
  "service-01/gf-ae-01" = "agent@test-project.iam.gserviceaccount.com"
  "service-01/iac-rw"   = "iac-rw@test-project.iam.gserviceaccount.com"
}

service_account_ids = {
  "service-01/gf-ae-01" = "projects/test-project/serviceAccounts/agent@test-project.iam.gserviceaccount.com"
  "service-01/iac-rw"   = "projects/test-project/serviceAccounts/iac-rw@test-project.iam.gserviceaccount.com"
}
