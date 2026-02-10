/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

project_config = {
  id     = "${projects.project.id}"
  number = "${projects.project.number}"
  prefix = "${projects.project.prefix}"
}
service_accounts = {
%{ for k,v in service_accounts ~}
  "${k}" = {
    email     = "${v.email}"
    iam_email = "${v.iam_email}"
    id        = "${v.id}"
  }
%{ endfor ~}
}
