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

import requests
import urllib3
import google.auth
import google.auth.transport.requests
from google.oauth2 import id_token

# Disable SSL warning due to private IP certificate handshakes
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

print("Initializing Google Cloud default credentials for OIDC auth...")
credentials, project = google.auth.default()
auth_req = google.auth.transport.requests.Request()

# Fetch the active identity OIDC token for the target Frontend Cloud Run service
audience = "https://gf-rrag-0-frontend-889035720634.europe-west1.run.app"
print(f"Fetching OIDC token for audience: {audience}...")
token = id_token.fetch_id_token(auth_req, audience)

headers = {"Authorization": f"Bearer {token}"}

print(
    "Starting VPC RAG endpoint prediction query to https://10.0.0.5/predict...")
try:
  response = requests.post(
      "https://10.0.0.5/predict",
      json={"prompt": "Recommend some space sci-fi movies in this database."},
      headers=headers, verify=False, timeout=30)
  print("HTTP STATUS CODE:", response.status_code)
  print("RAG RESPONSE RECEIVED:")
  print(response.json())
except Exception as e:
  print("Failed to query RAG frontend:", e)
