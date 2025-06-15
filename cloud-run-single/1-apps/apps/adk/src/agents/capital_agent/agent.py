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

# Code source and reworked from
# https://google.github.io/adk-docs/agents/llm-agents

import json

from google.adk.agents import LlmAgent
from pydantic import BaseModel, Field

from src import config


class CountryInput(BaseModel):
    country: str = Field(description="The country to get information about.")


class CapitalInfoOutput(BaseModel):
    capital: str = Field(description="The capital city of the country.")
    population_estimate: str = Field(
        description="An estimated population of the capital city.")


root_agent = LlmAgent(
    name="capital_agent",
    model=config.MODEL_NAME,
    description=
    "Provides capital and estimated population in a specific JSON format.",
    instruction=f"""You are an agent that provides country information.
The user will provide the country name in a JSON format like {{"country": "country_name"}}.
Respond ONLY with a JSON object matching this exact schema:
{json.dumps(CapitalInfoOutput.model_json_schema(), indent=2)}
Use your knowledge to determine the capital and estimate the population. Do not use any tools.
""",
    # *** NO tools parameter here - using output_schema prevents tool use ***
    input_schema=CountryInput,
    output_schema=CapitalInfoOutput,
    output_key="result",
)
