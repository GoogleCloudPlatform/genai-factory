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

from google.adk.agents.callback_context import CallbackContext
from google.adk.models.llm_request import LlmRequest
from google.adk.models.llm_response import LlmResponse
from google.api_core.client_options import ClientOptions
from google.cloud import modelarmor_v1
from src import config

logger = logging.getLogger(__name__)

model_armor_client = modelarmor_v1.ModelArmorClient(
    transport="rest",
    client_options=ClientOptions(
        api_endpoint=f"modelarmor.{config.REGION}.rep.googleapis.com"),
)


async def sanitize_request(callback_context: CallbackContext,
                           llm_request: LlmRequest) -> str:
  """
    Calls Model Armor API to inspect the prompt before the agents calls the LLM.

    Args:
        callback_context: The callback context containing information about the agent call.
        llm_request: The LLM request containing the prompt to inspect.

    Returns: None if the request is approved, or a modified request if the request is blocked.
    """

  if not config.MODEL_ARMOR_TEMPLATE:
    logger.warning(
        "MODEL_ARMOR_TEMPLATE environment variable not set. Skipping prompt inspection."
    )
    return None

  user_text = _extract_user_text(llm_request)
  if not user_text:
    return None

  logger.info(f"Screening user prompt")

  try:
    sanitize_request = modelarmor_v1.SanitizeUserPromptRequest(
        name=config.MODEL_ARMOR_TEMPLATE,
        user_prompt_data=modelarmor_v1.DataItem(text=user_text),
    )

    result = model_armor_client.sanitize_user_prompt(request=sanitize_request)
    matched_filters = result.sanitization_result.filter_match_state == modelarmor_v1.FilterMatchState.MATCH_FOUND

    if matched_filters:
      logger.warning(f"Blocked by Model Armor")
      # Overrides the user prompt with a message that fits the expected output schema
      return LlmResponse(
          content={
              "parts": [{
                  "text":
                      "{\"capital\": \"Blocked by Model Armor\", \"population_estimate\": \"N/A\"}"
              }],
              "role": "assistant"
          })
    else:
      logger.info("Model Armor approved the user request")
      return None  # Return None to preserve the original request

  except Exception as e:
    logger.error(f"Error while calling Model Armor: {e}", exc_info=True)
    return None


async def sanitize_response(callback_context: CallbackContext,
                            llm_response: LlmResponse) -> str:
  """
    Calls Model Armor API to inspect the response from the LLM.

    Args:
        callback_context: The callback context containing information about the agent call.
        llm_response: The LLM response containing the response to inspect.

    Returns: None if the response is approved, or a modified response if the response is blocked.
    """

  if not config.MODEL_ARMOR_TEMPLATE:
    logger.warning(
        "MODEL_ARMOR_TEMPLATE environment variable not set. Skipping prompt inspection."
    )
    return llm_response

  llm_response_text = _extract_model_text(llm_response)
  if not llm_response_text:
    return llm_response

  logger.info(f"Screening llm response")

  try:
    sanitize_request = modelarmor_v1.SanitizeUserPromptRequest(
        name=config.MODEL_ARMOR_TEMPLATE,
        user_prompt_data=modelarmor_v1.DataItem(text=llm_response),
    )

    result = model_armor_client.sanitize_user_prompt(request=sanitize_request)
    matched_filters = result.sanitization_result.filter_match_state == modelarmor_v1.FilterMatchState.MATCH_FOUND

    if matched_filters:
      logger.warning(f"Blocked by Model Armor")
      # Overrides the LLM response with a message that fits the expected output schema
      return LlmResponse(
          content={
              "parts": [{
                  "text":
                      "{\"capital\": \"Blocked by Model Armor\", \"population_estimate\": \"N/A\"}"
              }],
              "role": "assistant"
          })
    else:
      logger.info("Model Armor approved the LLM response")
      return None  # Return None to preserve the original response

  except Exception as e:
    logger.error(f"Error while calling Model Armor: {e}", exc_info=True)
    return None


def _extract_user_text(llm_request: LlmRequest) -> str:
  """Extract the user's text from the LLM request."""
  try:
    if llm_request.contents:
      for content in reversed(llm_request.contents):
        if content.role == "user":
          for part in content.parts:
            if hasattr(part, 'text') and part.text:
              return part.text
  except Exception as e:
    logger.error(f"Error extracting user text: {e}", exc_info=True)
  return ""


def _extract_model_text(llm_response: LlmResponse) -> str:
  """Extract the model's text from the LLM response."""
  try:
    if llm_response.content and llm_response.content.parts:
      for part in llm_response.content.parts:
        if hasattr(part, 'text') and part.text:
          return part.text
  except Exception as e:
    logger.error(f"Error extracting model text: {e}", exc_info=True)
  return ""
