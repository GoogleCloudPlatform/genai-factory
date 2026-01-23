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

import os

PROJECT_ID=os.environ.get("PROJECT_ID")
REGION=os.environ.get("REGION")

# TODO: to be checked periodically
# Update to gemini-3.0 when it works on regional endpoints
MODEL_NAME=os.environ.get("MODEL_NAME", "gemini-2.5-flash")

PROXY_ADDRESS=os.environ.get("PROXY_ADDRESS")
PROXY_PORT=os.environ.get("PROXY_PORT", "443")
