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

# variables from 0-projects

project_config = {
  id     = "prefix-gf-nl2sql-bq-0"
  number = "123456789012"
}
service_accounts = {
  "project/gf-nl2sql-bq-fe-0" = {
    email     = "gf-nl2sql-bq-fe-0@prefix-gf-nl2sql-bq-0.iam.gserviceaccount.com"
    iam_email = "serviceAccount:gf-nl2sql-bq-fe-0@prefix-gf-nl2sql-bq-0.iam.gserviceaccount.com"
    id        = "projects/prefix-gf-nl2sql-bq-0/serviceAccounts/gf-nl2sql-bq-fe-0@prefix-gf-nl2sql-bq-0.iam.gserviceaccount.com"
  }
  "project/gf-nl2sql-bq-fe-build-0" = {
    email     = "gf-nl2sql-bq-fe-build-0@prefix-gf-nl2sql-bq-0.iam.gserviceaccount.com"
    iam_email = "serviceAccount:gf-nl2sql-bq-fe-build-0@prefix-gf-nl2sql-bq-0.iam.gserviceaccount.com"
    id        = "projects/prefix-gf-nl2sql-bq-0/serviceAccounts/gf-nl2sql-bq-fe-build-0@prefix-gf-nl2sql-bq-0.iam.gserviceaccount.com"
  }
  "project/iac-rw" = {
    email     = "iac-rw@prefix-gf-nl2sql-bq-0.iam.gserviceaccount.com"
    iam_email = "serviceAccount:iac-rw@prefix-gf-nl2sql-bq-0.iam.gserviceaccount.com"
    id        = "projects/prefix-gf-nl2sql-bq-0/serviceAccounts/iac-rw@prefix-gf-nl2sql-bq-0.iam.gserviceaccount.com"
  }
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
