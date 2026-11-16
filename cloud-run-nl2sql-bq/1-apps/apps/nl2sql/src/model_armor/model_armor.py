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

import functools
import logging

from google.adk.agents.callback_context import CallbackContext
from google.adk.models.llm_request import LlmRequest
from google.adk.models.llm_response import LlmResponse
from google.api_core.client_options import ClientOptions
from google.cloud import modelarmor_v1
from google.genai import types

from src import config

logger = logging.getLogger(__name__)

_BLOCKED_PROMPT_MESSAGE = "Prompt was blocked by Model Armor."
_BLOCKED_RESPONSE_MESSAGE = "Response was blocked by Model Armor."


@functools.lru_cache(maxsize=1)
def _get_model_armor_client() -> modelarmor_v1.ModelArmorClient:
  """Lazily initializes and caches the regional Model Armor client."""
  return modelarmor_v1.ModelArmorClient(
      transport="rest",
      client_options=ClientOptions(
          api_endpoint=f"modelarmor.{config.REGION}.rep.googleapis.com"),
  )


def _blocked_llm_response(message: str) -> LlmResponse:
  """Builds a safe LlmResponse when Model Armor blocks content."""
  return LlmResponse(content=types.Content(
      role="model",
      parts=[types.Part.from_text(text=message)],
  ))


async def sanitize_request(
    callback_context: CallbackContext,
    llm_request: LlmRequest,
) -> LlmResponse | None:
  """Screens user prompts via Model Armor before invoking the LLM."""
  del callback_context
  if not config.MODEL_ARMOR_TEMPLATE:
    logger.warning("MODEL_ARMOR_TEMPLATE environment variable not set. "
                   "Skipping prompt inspection.")
    return None

  user_text = _extract_latest_user_text(llm_request)
  if not user_text:
    return None

  logger.debug("Screening user prompt with Model Armor.")
  try:
    request = modelarmor_v1.SanitizeUserPromptRequest(
        name=config.MODEL_ARMOR_TEMPLATE,
        user_prompt_data=modelarmor_v1.DataItem(text=user_text),
    )
    result = _get_model_armor_client().sanitize_user_prompt(request=request)
    matched = (result.sanitization_result.filter_match_state ==
               modelarmor_v1.FilterMatchState.MATCH_FOUND)
    if matched:
      logger.warning("User prompt blocked by Model Armor.")
      return _blocked_llm_response(_BLOCKED_PROMPT_MESSAGE)

    logger.debug("Model Armor approved the user prompt.")
    return None
  except Exception as e:
    logger.error("Error while calling Model Armor for prompt: %s", e,
                 exc_info=True)
    return _blocked_llm_response(_BLOCKED_PROMPT_MESSAGE)


async def sanitize_response(
    callback_context: CallbackContext,
    llm_response: LlmResponse,
) -> LlmResponse | None:
  """Screens LLM text responses via Model Armor before returning to caller."""
  del callback_context
  if not config.MODEL_ARMOR_TEMPLATE:
    logger.warning("MODEL_ARMOR_TEMPLATE environment variable not set. "
                   "Skipping response inspection.")
    return None

  llm_response_text = _extract_model_text(llm_response)
  if not llm_response_text:
    return None

  logger.debug("Screening LLM response with Model Armor.")
  try:
    request = modelarmor_v1.SanitizeModelResponseRequest(
        name=config.MODEL_ARMOR_TEMPLATE,
        model_response_data=modelarmor_v1.DataItem(text=llm_response_text),
    )
    result = _get_model_armor_client().sanitize_model_response(request=request)
    matched = (result.sanitization_result.filter_match_state ==
               modelarmor_v1.FilterMatchState.MATCH_FOUND)
    if matched:
      logger.warning("LLM response blocked by Model Armor.")
      return _blocked_llm_response(_BLOCKED_RESPONSE_MESSAGE)

    logger.debug("Model Armor approved the LLM response.")
    return None
  except Exception as e:
    logger.error("Error while calling Model Armor for response: %s", e,
                 exc_info=True)
    return _blocked_llm_response(_BLOCKED_RESPONSE_MESSAGE)


def _extract_latest_user_text(llm_request: LlmRequest) -> str:
  """Extracts text parts if the latest turn in the request is user text."""
  if not llm_request.contents:
    return ""
  latest = llm_request.contents[-1]
  if latest.role != "user" or not latest.parts:
    return ""
  texts = [part.text for part in latest.parts if part.text]
  return "\n".join(texts)


def _extract_model_text(llm_response: LlmResponse) -> str:
  """Extracts all text parts from an LLM response."""
  if not llm_response.content or not llm_response.content.parts:
    return ""
  texts = [part.text for part in llm_response.content.parts if part.text]
  return "\n".join(texts)
