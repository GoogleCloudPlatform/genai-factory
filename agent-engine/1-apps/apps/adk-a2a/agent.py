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

import vertexai

# from google.adk.agents import Agent
from vertexai.agent_engines import AdkApp
from vertexai import Client, agent_engines
from google.genai import types
from vertexai.preview.reasoning_engines.templates.a2a import create_agent_card

from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types import TaskState, TextPart, UnsupportedOperationError, Part
from a2a.utils import new_agent_text_message
from a2a.utils.errors import ServerError
from google.adk import Runner
from google.adk.agents import LlmAgent
from google.adk.artifacts import InMemoryArtifactService
from google.adk.memory.in_memory_memory_service import InMemoryMemoryService
from google.adk.sessions import InMemorySessionService

from vertexai.preview.reasoning_engines import A2aAgent

from google.adk.a2a.utils.agent_to_a2a import to_a2a
from a2a.types import AgentCard, AgentSkill


# Define A2A the skill for the CurrencyAgent
currency_skill = AgentSkill(
    id='get_exchange_rate',
    name='Get Currency Exchange Rate',
    description='Retrieves the exchange rate between two currencies on a specified date.',
    tags=['Finance', 'Currency', 'Exchange Rate'],
    examples=[
        'What is the exchange rate from USD to EUR?',
        'How many Japanese Yen is 1 US dollar worth today?',
    ],
)

# Create the A2A agent card using the utility function
agent_card = create_agent_card(
    agent_name='Currency Exchange Agent',
    description='An agent that can provide currency exchange rates',
    skills=[currency_skill]
)

def get_exchange_rate(
    currency_from: str = "USD",
    currency_to: str = "EUR",
    currency_date: str = "latest",
):
    """Retrieves the exchange rate between two currencies on a specified date.

    Uses the Frankfurter API (https://api.frankfurter.app/) to obtain
    exchange rate data.

    Args:
        currency_from: The base currency (3-letter currency code).
            Defaults to "USD" (US Dollar).
        currency_to: The target currency (3-letter currency code).
            Defaults to "EUR" (Euro).
        currency_date: The date for which to retrieve the exchange rate.
            Defaults to "latest" for the most recent exchange rate data.
            Can be specified in YYYY-MM-DD format for historical rates.

    Returns:
        dict: A dictionary containing the exchange rate information.
            Example: {"amount": 1.0, "base": "USD", "date": "2023-11-24",
                "rates": {"EUR": 0.95534}}
    """
    import requests

    params = {
        "from": currency_from,
        "to": currency_to
    }
    proxies = {
        "http"  : "http://192.168.1.2:3128",
        "https" : "http://192.168.1.2:3128"
    }

    response = requests.get(
        f"https://api.frankfurter.app/{currency_date}",
        params=params,
        proxies=proxies
    )
    return response.json()

class CurrencyAgentExecutorWithRunner(AgentExecutor):
    """Executor that takes an LlmAgent instance and initializes the ADK Runner internally."""

    def __init__(self, agent: LlmAgent):
        self.agent = agent
        self.runner = None

    def _init_adk(self):
        if not self.runner:
            self.runner = Runner(
                app_name=self.agent.name,
                agent=self.agent,
                artifact_service=InMemoryArtifactService(),
                session_service=InMemorySessionService(),
                memory_service=InMemoryMemoryService(),
            )

    async def cancel(self, context: RequestContext, event_queue: EventQueue):
        raise ServerError(error=UnsupportedOperationError())

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        self._init_adk() # Initialize on first execute call

        if not context.message:
            return

        user_id = context.message.metadata.get('user_id') if context.message and context.message.metadata else 'a2a_user'

        updater = TaskUpdater(event_queue, context.task_id, context.context_id)
        if not context.current_task:
            await updater.submit()
        await updater.start_work()

        query = context.get_user_input()
        content = types.Content(role='user', parts=[types.Part(text=query)])

        try:
            session = await self.runner.session_service.get_session(
                app_name=self.runner.app_name,
                user_id=user_id,
                session_id=context.context_id,
            ) or await self.runner.session_service.create_session(
                app_name=self.runner.app_name,
                user_id=user_id,
                session_id=context.context_id,
            )

            final_event = None
            async for event in self.runner.run_async(
                session_id=session.id,
                user_id=user_id,
                new_message=content
            ):
                if event.is_final_response():
                    final_event = event

            if final_event and final_event.content and final_event.content.parts:
                response_text = "".join(
                    part.text for part in final_event.content.parts if hasattr(part, 'text') and part.text
                )
                if response_text:
                    await updater.add_artifact(
                        [TextPart(text=response_text)],
                        name='result',
                    )
                    await updater.complete()
                    return

            await updater.update_status(
                TaskState.failed,
                message=new_agent_text_message('Failed to generate a final response with text content.'),
                final=True
            )

        except Exception as e:
            await updater.update_status(
                TaskState.failed,
                message=new_agent_text_message(f"An error occurred: {str(e)}"),
                final=True,
            )

local_agent = LlmAgent(
   model='gemini-3.0-flash',
   name='test_a2a_psc_i_agent',
   description='A test A2A agent with PSC-I.',
   tools=[get_exchange_rate]
)

a2a_agent = A2aAgent(
    agent_card=agent_card,
    agent_executor_builder=lambda: CurrencyAgentExecutorWithRunner(
        agent=local_agent,
    )
)

a2a_agent.set_up()
