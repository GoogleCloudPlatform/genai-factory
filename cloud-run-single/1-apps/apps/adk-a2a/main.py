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

import logging
import os
from urllib.parse import urlparse

from google.adk.a2a.utils.agent_to_a2a import to_a2a
import uvicorn

from src import config
from src.agents.capital_agent.agent import agent

os.environ["GOOGLE_CLOUD_PROJECT"] = config.PROJECT_ID
os.environ["GOOGLE_CLOUD_LOCATION"] = config.REGION
os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = config.GOOGLE_GENAI_USE_VERTEXAI

logging.basicConfig(level=logging.INFO)

parsed_url = urlparse(config.A2A_HOST)
A2A_HOST = parsed_url.netloc or config.A2A_HOST

logging.debug(f"A2A_URL: {config.A2A_HOST}")
logging.debug(f"A2A_PORT: {config.A2A_PORT}")
logging.debug(f"A2A_PROTOCOL: {config.A2A_PROTOCOL}")
logging.debug(f"INTERNAL_HOST: {config.INTERNAL_HOST}")
logging.debug(f"INTERNAL_PORT: {config.INTERNAL_PORT}")

app = to_a2a(agent=agent,
             protocol=config.A2A_PROTOCOL,
             host=config.A2A_HOST,
             port=config.A2A_PORT)

if __name__ == "__main__":
    uvicorn.run(app, host=config.INTERNAL_HOST, port=config.INTERNAL_PORT)
