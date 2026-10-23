#!/usr/bin/env python

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

import os
import sys
from typing import Any, Dict
import fastapi
import requests

import vertexai
from google.adk import Runner
from google.adk.agents import LlmAgent
from src.firestore_artifact_service import FirestoreArtifactService
from src.firestore_memory_service import FirestoreMemoryService
from src.firestore_session_service import FirestoreSessionService
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

from src import config

os.environ["GOOGLE_CLOUD_LOCATION"] = config.GOOGLE_CLOUD_LOCATION

vertexai.init(
    project=config.PROJECT_ID,
    location=config.REGION,
)

client = vertexai.Client(
    project=config.PROJECT_ID,
    location=config.REGION,
)

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
    os.environ["GOOGLE_CLOUD_LOCATION"] = config.GOOGLE_CLOUD_LOCATION
    # Initialize the ADK Runner
    if not self.runner:
      self.runner = Runner(
          app_name=self.agent.name,
          agent=self.agent,
          artifact_service=FirestoreArtifactService(
              project_id=config.PROJECT_ID,
              database=config.FIRESTORE_DATABASE,
          ),
          session_service=FirestoreSessionService(
              project_id=config.PROJECT_ID,
              database=config.FIRESTORE_DATABASE,
          ),
          memory_service=FirestoreMemoryService(
              project_id=config.PROJECT_ID,
              database=config.FIRESTORE_DATABASE,
          ),
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
          TaskState.failed, message=new_agent_text_message(
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
  proxies = None
  if getattr(config, 'ENABLE_PSC_I', True):
    proxies = {
        "http": f"http://{config.PROXY_ADDRESS}:{config.PROXY_PORT}",
        "https": f"http://{config.PROXY_ADDRESS}:{config.PROXY_PORT}",
    }
  try:
    response = requests.get(f"https://api.frankfurter.dev/v1/{currency_date}",
                            params={
                                "from": currency_from,
                                "to": currency_to
                            }, proxies=proxies)
    response.raise_for_status()
    return response.json()
  except requests.exceptions.RequestException as e:
    return {"error": str(e)}


from src.firestore_task_store import FirestoreTaskStore

llm_agent = LlmAgent(
    model=config.MODEL_NAME,
    name='currency_exchange_agent',
    description='An agent that can provide currency exchange rates.',
    instruction="""You are a helpful currency exchange assistant.
                   Use the get_exchange_rate tool to answer user questions.
                   If the tool returns an error, inform the user about the error.""",
    tools=[get_exchange_rate],
    generate_content_config=types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(
            thinking_level=config.THINKING_LEVEL),),
)


class WellKnownCardA2aAgent(A2aAgent):
  """A2aAgent subclass that also exposes the A2A Agent Card at /.well-known/agent-card.json."""

  def set_up(self):
    super().set_up()
    self._register_well_known_agent_card_routes()

  def _get_agent_card_dict(self) -> Dict[str, Any]:
    if hasattr(self.agent_card, "model_dump"):
      return self.agent_card.model_dump(mode="json", by_alias=True,
                                        exclude_none=True)
    return dict(self.agent_card)

  def _register_well_known_agent_card_routes(self) -> None:
    """Registers /.well-known/agent-card.json on the Reasoning Engine FastAPI app."""
    agent_self = self

    async def serve_well_known_agent_card(request: fastapi.Request):
      return fastapi.responses.JSONResponse(
          content=agent_self._get_agent_card_dict())

    well_known_paths = (
        "/.well-known/agent-card.json",
        "/.well-known/agent.json",
        "/a2a/.well-known/agent-card.json",
        "/a2a/.well-known/agent.json",
    )

    def _ensure_routes(target: Any, prefix: str = "") -> None:
      existing = {
          getattr(r, "path", None) for r in getattr(target, "routes", [])
      }
      for path in well_known_paths:
        full_path = f"{prefix}{path}"
        if full_path not in existing:
          target.add_api_route(full_path, serve_well_known_agent_card,
                               methods=["GET"])
          existing.add(full_path)

    if not getattr(fastapi.FastAPI, "_well_known_card_patched", False):
      orig_fastapi_init = fastapi.FastAPI.__init__

      def patched_fastapi_init(fastapi_app, *args, **kwargs):
        orig_fastapi_init(fastapi_app, *args, **kwargs)
        _ensure_routes(fastapi_app, "")
        _ensure_routes(fastapi_app, "/api")

      fastapi.FastAPI.__init__ = patched_fastapi_init
      fastapi.FastAPI._well_known_card_patched = True

    for mod in list(sys.modules.values()):
      orig_create = getattr(mod, "_create_app_from_router", None)
      if callable(orig_create) and not getattr(
          orig_create, "_well_known_card_patched", False):

        def _make_patched(fn):

          def _patched(router, metrics_state=None):
            if router is not None:
              _ensure_routes(router, "")
            app_instance = fn(router, metrics_state)
            _ensure_routes(app_instance, "")
            _ensure_routes(app_instance, "/api")
            return app_instance

          _patched._well_known_card_patched = True
          return _patched

        try:
          setattr(mod, "_create_app_from_router", _make_patched(orig_create))
        except Exception:
          pass


agent = WellKnownCardA2aAgent(
    agent_card=agent_card,
    agent_executor_builder=lambda: CurrencyAgentExecutorWithRunner(agent=
                                                                   llm_agent),
    task_store_builder=lambda: FirestoreTaskStore(
        project_id=config.PROJECT_ID,
        database=config.FIRESTORE_DATABASE,
    ),
)
agent.set_up()
