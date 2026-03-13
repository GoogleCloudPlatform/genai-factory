import requests

import vertexai
from google.adk import Runner
from google.adk.agents import LlmAgent
from google.adk.artifacts import InMemoryArtifactService
from google.adk.memory.in_memory_memory_service import InMemoryMemoryService
from google.adk.sessions import InMemorySessionService
from google.genai import types
from vertexai import Client, agent_engines
from vertexai.preview.reasoning_engines import A2aAgent
from vertexai.preview.reasoning_engines.templates.a2a import create_agent_card

from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types import (
    AgentCard,
    AgentSkill,
    Part,
    TaskState,
    TextPart,
    UnsupportedOperationError,
)
from a2a.utils import new_agent_text_message
from a2a.utils.errors import ServerError

vertexai.init(project="xxxx",
              location="europe-west1",
              staging_bucket="gs://xxxx")

client = vertexai.Client(
    project="xxxx",
    location="europe-west1",
)

requirements = [
    "a2a-sdk>=0.3.4",
    "cloudpickle==3.0",
    "google-cloud-aiplatform[agent_engines, adk]"
]

# Define the skill for the CurrencyAgent
currency_skill = AgentSkill(
    id='get_exchange_rate',
    name='Get Currency Exchange Rate',
    description=
    'Retrieves the exchange rate between two currencies on a specified date.',
    tags=['Finance', 'Currency', 'Exchange Rate'],
    examples=[
        'What is the exchange rate from USD to EUR?',
        'How many Japanese Yen is 1 US dollar worth today?',
    ],
)

# Create the agent card using the utility function
agent_card = create_agent_card(
    agent_name='Currency Exchange Agent',
    description='An agent that can provide currency exchange rates',
    skills=[currency_skill])


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
        self._init_adk()  # Initialize on first execute call

        if not context.message:
            return

        user_id = context.message.metadata.get(
            'user_id'
        ) if context.message and context.message.metadata else 'a2a_user'

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
            async for event in self.runner.run_async(session_id=session.id,
                                                     user_id=user_id,
                                                     new_message=content):
                if event.is_final_response():
                    final_event = event

            if final_event and final_event.content and final_event.content.parts:
                response_text = "".join(part.text
                                        for part in final_event.content.parts
                                        if hasattr(part, 'text') and part.text)
                if response_text:
                    await updater.add_artifact(
                        [TextPart(text=response_text)],
                        name='result',
                    )
                    await updater.complete()
                    return

            await updater.update_status(
                TaskState.failed,
                message=new_agent_text_message(
                    'Failed to generate a final response with text content.'),
                final=True)

        except Exception as e:
            await updater.update_status(
                TaskState.failed,
                message=new_agent_text_message(f"An error occurred: {str(e)}"),
                final=True,
            )


def get_exchange_rate(
    currency_from: str = "USD",
    currency_to: str = "EUR",
    currency_date: str = "latest",
):
    """Retrieves the exchange rate between two currencies on a specified date.
    Uses the Frankfurter API (https://api.frankfurter.app/) to obtain
    exchange rate data.
    """
    try:
        response = requests.get(
            f"https://api.frankfurter.app/{currency_date}",
            params={
                "from": currency_from,
                "to": currency_to
            },
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        return {"error": str(e)}


llm_agent = LlmAgent(
    model='gemini-2.5-flash',
    name='currency_exchange_agent',
    description='An agent that can provide currency exchange rates.',
    instruction="""You are a helpful currency exchange assistant.
                   Use the get_exchange_rate tool to answer user questions.
                   If the tool returns an error, inform the user about the error.""",
    tools=[get_exchange_rate],
)

agent = A2aAgent(
    agent_card=agent_card,
    agent_executor_builder=lambda: CurrencyAgentExecutorWithRunner(
        agent=llm_agent, ))
agent.set_up()

remote_agent = agent_engines.create(
    agent,
    requirements=requirements,
)
