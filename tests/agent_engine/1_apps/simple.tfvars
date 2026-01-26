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
project_config = {
  id     = "test-project"
  number = "123456789"
}
region = "europe-west1"
service_accounts = {
  "project/gf-ae-0" = {
    email     = "agent@test-project.iam.gserviceaccount.com"
    iam_email = "serviceAccount:agent@test-project.iam.gserviceaccount.com"
    id        = "projects/test-project/serviceAccounts/agent@test-project.iam.gserviceaccount.com"
  }
  "project/iac-rw" = {
    email     = "iac-rw@test-project.iam.gserviceaccount.com"
    iam_email = "serviceAccount:iac-rw@test-project.iam.gserviceaccount.com"
    id        = "projects/test-project/serviceAccounts/iac-rw@test-project.iam.gserviceaccount.com"
  }
}
