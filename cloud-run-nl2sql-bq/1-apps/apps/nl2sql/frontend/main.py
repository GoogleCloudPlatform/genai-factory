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
import sys

import uvicorn
from google.adk.cli.fast_api import get_fast_api_app

from src import config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

logger.info("Starting up FastAPI application...")
logger.info(f"Project ID: {config.PROJECT_ID}")
logger.info(f"BQ Compute Project ID: {config.BQ_COMPUTE_PROJECT_ID}")
logger.info(f"BQ Data Project ID: {config.BQ_DATA_PROJECT_ID}")
logger.info(f"BQ Dataset ID: {config.BQ_DATASET_ID}")
logger.info(f"Agents Directory: {config.AGENT_DIR}")

app = get_fast_api_app(
    agents_dir=config.AGENT_DIR,
    allow_origins=config.ALLOWED_ORIGINS,
    web=config.SERVE_WEB_INTERFACE,
)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=config.INTERNAL_PORT)
