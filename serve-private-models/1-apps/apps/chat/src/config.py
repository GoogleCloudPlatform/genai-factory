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

PROJECT_ID = os.environ.get("PROJECT_ID")
REGION = os.environ.get("REGION", "europe-west4")
ENDPOINT_ID = os.environ.get("ENDPOINT_ID")
ENDPOINT_IP_ADDRESS = os.environ.get("ENDPOINT_IP_ADDRESS")

TEMPERATURE = float(os.environ.get("TEMPERATURE", "0.9"))
TOP_P = float(os.environ.get("TOP_P", "1.0"))
TOP_K = int(os.environ.get("TOP_K", "32"))
CANDIDATE_COUNT = int(os.environ.get("CANDIDATE_COUNT", "1"))
MAX_OUTPUT_TOKENS = int(os.environ.get("MAX_OUTPUT_TOKENS", "1024"))
MODEL_ARMOR_TEMPLATE = os.environ.get("MODEL_ARMOR_TEMPLATE")
