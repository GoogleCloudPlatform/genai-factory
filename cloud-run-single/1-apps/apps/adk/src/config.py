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

MODEL_NAME = os.environ.get("MODEL_NAME", "gemini-2.0-flash")

AGENT_DIR = os.environ.get(
    "AGENT_DIR",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "agents"))
ALLOWED_ORIGINS = os.environ.get("ALLOWED_ORIGINS", ["*"])
SERVE_WEB_INTERFACE = os.environ.get("SERVE_WEB_INTERFACE", False)
SESSION_DB_URL = os.environ.get("SESSION_DB_URL", "sqlite:///./sessions.db")
