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

import os

A2A_HOST = os.environ.get("A2A_HOST", "localhost")
A2A_PORT = int(os.environ.get("A2A_PORT", 443))
A2A_PROTOCOL = os.environ.get("A2A_PROTOCOL", "https")

INTERNAL_HOST = "0.0.0.0"
INTERNAL_PORT = int(os.environ.get("PORT", 8003))

MODEL_NAME = os.environ.get("MODEL_NAME", "gemini-2.5-flash")

PROJECT_ID = os.environ.get("PROJECT_ID")

REGION = os.environ.get("REGION", "europe-west1")

GOOGLE_GENAI_USE_VERTEXAI = os.environ.get("GOOGLE_GENAI_USE_VERTEXAI", "1")
