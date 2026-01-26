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

from google.adk.agents import LlmAgent
import vertexai
from vertexai.agent_engines import AdkApp

import requests

from src import config

vertexai.init(
    project=config.PROJECT_ID,
    location=config.REGION,
)

def get_exchange_rate(
    currency_from: str = "USD",
    currency_to: str = "EUR",
    currency_date: str = "latest",
):
    proxies = None
    if getattr(config, 'ENABLE_PSC_I', True):
        proxies = {
            "http": f"http://{config.PROXY_ADDRESS}:{config.PROXY_PORT}",
            "https": f"http://{config.PROXY_ADDRESS}:{config.PROXY_PORT}",
        }
    response = requests.get(
        f"https://api.frankfurter.app/{currency_date}",
        params={"from": currency_from, "to": currency_to},
        proxies=proxies
    )
    return response.json()

root_agent = LlmAgent(
    model=config.MODEL_NAME,
    instruction="You are a helpful assistant",
    name='currency_exchange_agent',
    tools=[get_exchange_rate],
)

agent = AdkApp(agent=root_agent)
