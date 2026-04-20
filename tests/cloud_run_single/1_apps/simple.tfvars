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

# variables from 0-prereqs

prefix     = "prefix"
project_id = "your-project"
number     = "123456789012"

networking_config = {
  subnet = "projects/prefix-gf-srun-hp-0/regions/europe-west1/subnetworks/sub-0"
  vpc    = "projects/prefix-gf-srun-hp-0/global/networks/net-0"
}

region = "europe-west1"

service_account_emails = {
  "service-01/crun-0"       = "crun-0@prefix-gf-srun-0.iam.gserviceaccount.com"
  "service-01/crun-build-0" = "crun-build-0@prefix-gf-srun-0.iam.gserviceaccount.com"
  "service-01/iac-rw"       = "iac-rw@prefix-gf-srun-0.iam.gserviceaccount.com"
}
service_account_ids = {
  "service-01/crun-0"       = "projects/prefix-gf-srun-0/serviceAccounts/crun-0@prefix-gf-srun-0.iam.gserviceaccount.com"
  "service-01/crun-build-0" = "projects/prefix-gf-srun-0/serviceAccounts/crun-build-0@prefix-gf-srun-0.iam.gserviceaccount.com"
  "service-01/iac-rw"       = "projects/prefix-gf-srun-0/serviceAccounts/iac-rw@prefix-gf-srun-0.iam.gserviceaccount.com"
}

# variables from 1-apps

lbs_config = {
  external = {
    domain = "your-domain.com"
  }
  internal = {
    enable = true
  }
}
