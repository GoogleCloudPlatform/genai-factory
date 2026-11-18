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
import json
import logging
from collections.abc import Mapping
from typing import Any

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
  """Screens user prompts and tool payloads via Model Armor before invoking the LLM."""
  del callback_context
  if not config.MODEL_ARMOR_TEMPLATE:
    logger.warning("MODEL_ARMOR_TEMPLATE environment variable not set. "
                   "Skipping prompt inspection.")
    return None

  try:
    user_text = _extract_user_text(llm_request)
    if not user_text:
      return None

    logger.debug("Screening user prompt with Model Armor.")
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
  """Screens LLM responses and tool calls via Model Armor before returning to caller."""
  del callback_context
  if not config.MODEL_ARMOR_TEMPLATE:
    logger.warning("MODEL_ARMOR_TEMPLATE environment variable not set. "
                   "Skipping response inspection.")
    return None

  try:
    llm_response_text = _extract_model_text(llm_response)
    if not llm_response_text:
      return None

    logger.debug("Screening LLM response with Model Armor.")
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


def _get_field(obj: Any, name: str) -> Any:
  """Reads an attribute or mapping key safely."""
  if isinstance(obj, Mapping):
    return obj.get(name)
  return getattr(obj, name, None)


def _serialize_payload(payload: Any) -> str:
  """Serializes structured tool call/response payloads deterministically."""
  if hasattr(payload, "model_dump"):
    payload = payload.model_dump(mode="json", exclude_none=True)
  return json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)


def _extract_part_segments(part: Any) -> list[str]:
  """Extracts all inspectable text and structured payloads from a single Part."""
  segments: list[str] = []

  text = _get_field(part, "text")
  if isinstance(text, str) and text:
    segments.append(text)
  elif text is not None and text != "":
    segments.append(str(text))

  function_call = _get_field(part, "function_call")
  if function_call is not None:
    segments.append(
        _serialize_payload({
            "function_call": {
                "name": _get_field(function_call, "name"),
                "args": _get_field(function_call, "args"),
            }
        }))

  function_response = _get_field(part, "function_response")
  if function_response is not None:
    segments.append(
        _serialize_payload({
            "function_response": {
                "name": _get_field(function_response, "name"),
                "response": _get_field(function_response, "response"),
            }
        }))

  executable_code = _get_field(part, "executable_code")
  if executable_code is not None:
    code = _get_field(executable_code, "code")
    if code:
      segments.append(str(code))

  code_execution_result = _get_field(part, "code_execution_result")
  if code_execution_result is not None:
    output = _get_field(code_execution_result, "output")
    if output:
      segments.append(str(output))

  return segments


def _extract_user_text(llm_request: LlmRequest) -> str:
  """Extracts all text and tool payloads across all user-role contents."""
  contents = _get_field(llm_request, "contents")
  if not contents:
    return ""

  segments: list[str] = []
  for content in contents:
    if content is None:
      continue
    role = _get_field(content, "role")
    if role not in (None, "user"):
      continue
    parts = _get_field(content, "parts") or []
    for part in parts:
      if part is not None:
        segments.extend(_extract_part_segments(part))
  return "\n".join(segments)


def _extract_model_text(llm_response: LlmResponse) -> str:
  """Extracts all text, thought, and tool-call payloads across response parts."""
  content = _get_field(llm_response, "content")
  if not content:
    return ""
  parts = _get_field(content, "parts") or []
  segments: list[str] = []
  for part in parts:
    if part is not None:
      segments.extend(_extract_part_segments(part))
  return "\n".join(segments)
