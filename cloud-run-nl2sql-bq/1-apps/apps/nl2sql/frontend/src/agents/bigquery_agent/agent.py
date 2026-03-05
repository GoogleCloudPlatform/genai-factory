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

# Code source and reworked from
# https://google.github.io/adk-docs/agents/llm-agents

import logging
import os
from datetime import date

from google.adk.agents import LlmAgent
from google.adk.agents.callback_context import CallbackContext
from google.adk.models import Gemini
from google.adk.tools.bigquery import BigQueryToolset
from google.adk.tools.bigquery.config import BigQueryToolConfig, WriteMode
from google.genai import types

from src import config
from src.agents.bigquery_agent.prompts import ROOT_AGENT_PROMPT
from src.agents.bigquery_agent.utils import (
    get_database_settings,
    get_dataset_definitions_for_instructions,
)

os.environ["GOOGLE_CLOUD_PROJECT"] = os.environ["PROJECT_ID"]
os.environ["GOOGLE_CLOUD_LOCATION"] = os.environ["REGION"]
os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "1"

# Set up logging
logger = logging.getLogger(__name__)

# Tool setup for a minimal bigquery nl2sql agent
bigquery_tool_config = BigQueryToolConfig(write_mode=WriteMode.BLOCKED)
bigquery_toolset = BigQueryToolset(
    tool_filter=["execute_sql"], bigquery_tool_config=bigquery_tool_config
)


def get_root_agent() -> LlmAgent:
    """Creates and returns the root agent."""
    logger.info("Initializing the bigquery_agent...")
    database_settings = get_database_settings()
    logger.info("Successfully loaded database settings during agent initialization.")

    def load_database_settings_in_context(callback_context: CallbackContext):
        """Load database settings into the callback context on first use."""
        session_id = (
            callback_context.session.id if callback_context.session else "Unknown"
        )
        logger.info(f"[Session: {session_id}] Executing before_agent_callback.")

        if "database_settings" not in callback_context.state:
            logger.info(
                f"[Session: {session_id}] loading database_settings into context state."
            )
            callback_context.state["database_settings"] = database_settings
        else:
            logger.info(
                f"[Session: {session_id}] database_settings already present in context state."
            )

    return LlmAgent(
        model=Gemini(
            model=config.ROOT_AGENT_MODEL,
            retry_options=types.HttpRetryOptions(
                attempts=5,
                http_status_codes=[
                    429,  # Too Many Requests
                    500,  # Internal Server Error
                    503,  # Service Unavailable
                    504,  # Gateway Timeout
                ],
                exp_base=2.0,
                initial_delay=1.0,
                max_delay=60.0,
            ),
        ),
        name="bigquery_agent",
        instruction=(
            ROOT_AGENT_PROMPT.format(
                bq_data_project_id=config.PROJECT_ID, bq_dataset_id=config.BQ_DATASET_ID
            )
            + get_dataset_definitions_for_instructions(database_settings)
        ),
        global_instruction=(
            f"You are a Data Science and Data Analytics Multi Agent System. Today's date: {date.today()}\n"
        ),
        tools=[bigquery_toolset],
        before_agent_callback=load_database_settings_in_context,
        generate_content_config=types.GenerateContentConfig(
            temperature=0.01, http_options=types.HttpOptions(timeout=120000)
        ),
    )


# Initialize the root agent and the application
root_agent = get_root_agent()
