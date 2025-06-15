# Copyright 2025 Google LLC
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

PROJECT_ID = os.environ.get("PROJECT_ID")
REGION = os.environ.get("REGION", "europe-west1")

AGENT_DIR = os.environ.get("AGENT_DIR", "src/agents")

ALLOWED_ORIGINS = ["http://localhost", "http://localhost:8080", "*"]

SESSION_DB_URL = os.environ.get("SESSION_DB_URL", "sqlite:///./sessions.db")

SERVE_WEB_INTERFACE = os.environ.get("SERVE_WEB_INTERFACE", False)
