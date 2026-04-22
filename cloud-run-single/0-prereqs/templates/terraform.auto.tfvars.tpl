/**
 * Copyright 2026 Google LLC
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

networking_config = {
  subnet = "${try(networking_config.subnet, "")}"
  vpc    = "${try(networking_config.vpc, "")}"
}

prefix = "${prefix}"

project_id = "${project_id}"
number     = "${project_number}"

region = "${region}"

service_account_emails = {
%{ for k,v in service_account_emails ~}
  "${k}" = "${v}"
%{ endfor ~}
}

service_account_ids = {
%{ for k,v in service_account_ids ~}
  "${k}" = "${v}"
%{ endfor ~}
}
