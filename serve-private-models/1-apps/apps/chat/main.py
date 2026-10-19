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
from typing import Any
from fastapi import FastAPI, HTTPException
from google.api_core.client_options import ClientOptions
import google.api_core.exceptions as exceptions
from google.cloud import aiplatform
import google.cloud.logging
from google.cloud import modelarmor_v1

import uvicorn
from src import config
from src.request_model import Prompt

app = FastAPI(title=__name__)

# Configure logging
client = google.cloud.logging.Client()
client.setup_logging(log_level=logging.INFO)

logger = logging.getLogger()
logger.setLevel(logging.INFO)

logger.info(
    "Initializing Vertex AI PrivateEndpoint for project=%s, region=%s, endpoint=%s",
    config.PROJECT_ID,
    config.REGION,
    config.ENDPOINT_ID,
)
aiplatform.init(project=config.PROJECT_ID, location=config.REGION)
private_endpoint = (aiplatform.PrivateEndpoint(
    endpoint_name=config.ENDPOINT_ID) if config.ENDPOINT_ID else None)
logger.info("Vertex AI PrivateEndpoint initialized successfully.")
logger.debug("Model armor template: %s", config.MODEL_ARMOR_TEMPLATE)

model_armor_client = modelarmor_v1.ModelArmorClient(
    transport="rest",
    client_options=ClientOptions(
        api_endpoint=f"modelarmor.{config.REGION}.rep.googleapis.com"),
)


def _is_blocked_by_model_armor(text: str) -> bool:
  """Calls Model Armor API to inspect text if a template is configured."""
  if not config.MODEL_ARMOR_TEMPLATE or not text:
    return False
  sanitize_request = modelarmor_v1.SanitizeUserPromptRequest(
      name=config.MODEL_ARMOR_TEMPLATE,
      user_prompt_data=modelarmor_v1.DataItem(text=text),
  )
  result = model_armor_client.sanitize_user_prompt(request=sanitize_request)
  return (result.sanitization_result.filter_match_state ==
          modelarmor_v1.FilterMatchState.MATCH_FOUND)


def _extract_prediction_text(predictions: Any) -> str:
  """Extracts text from Model Garden container prediction responses."""
  if isinstance(predictions, dict):
    choices = predictions.get("choices", [])
    if choices and isinstance(choices[0], dict):
      msg = choices[0].get("message", {})
      if isinstance(msg, dict) and "content" in msg:
        return str(msg["content"])
      if "text" in choices[0]:
        return str(choices[0]["text"])
    return str(predictions)
  if isinstance(predictions, list) and predictions:
    first = predictions[0]
    if isinstance(first, dict):
      choices = first.get("choices", [])
      if choices and isinstance(choices[0], dict):
        msg = choices[0].get("message", {})
        if isinstance(msg, dict) and "content" in msg:
          return str(msg["content"])
      if "content" in first:
        return str(first["content"])
    return str(first)
  return ""


@app.get("/")
async def root():
  """Basic health check / info endpoint."""

  return {
      "message": "Vertex AI Private Endpoint Sample App is running.",
      "project_id": config.PROJECT_ID,
      "region": config.REGION,
      "model_endpoint_id": config.ENDPOINT_ID,
  }


@app.post("/predict")
async def predict_route(request: Prompt):
  """Endpoint to make a prediction using Vertex AI Private Endpoint over PSC."""

  if private_endpoint is None or not config.ENDPOINT_IP_ADDRESS:
    logger.error("Vertex AI PrivateEndpoint or ENDPOINT_IP_ADDRESS not set.")
    raise HTTPException(
        status_code=500,
        detail="Internal server error: Model endpoint not initialized.",
    )

  logger.debug("Received prediction request with prompt: '%s...'",
               request.prompt[:100])

  try:
    if _is_blocked_by_model_armor(request.prompt):
      logger.warning("User prompt was blocked by Model Armor.")
      return {
          "prompt": request.prompt,
          "prediction": "Prompt was blocked by Model Armor.",
      }

    instances = [{
        "@requestFormat": "chatCompletions",
        "messages": [{
            "role": "user",
            "content": request.prompt,
        }],
        "max_tokens": config.MAX_OUTPUT_TOKENS,
        "temperature": config.TEMPERATURE,
        "top_p": config.TOP_P,
    }]

    response = private_endpoint.predict(
        instances=instances,
        endpoint_override=config.ENDPOINT_IP_ADDRESS,
    )

    # --- Process Response ---
    prediction_text = _extract_prediction_text(response.predictions)
    if prediction_text:
      if _is_blocked_by_model_armor(prediction_text):
        logger.warning("Model response was blocked by Model Armor.")
        prediction_text = "Response was blocked by Model Armor."
      else:
        logger.debug("Successfully received prediction from Vertex AI: %s",
                     prediction_text[:100])
    else:
      prediction_text = "Prompt was blocked by Model Armor."
      logger.warning(
          "Vertex AI returned an empty response. It may have been blocked by Model Armor."
      )

  except (exceptions.GoogleAPIError, ValueError, RuntimeError) as e:
    logger.error("Vertex AI PrivateEndpoint call failed: %s", e, exc_info=True)
    prediction_text = "Failed to get an answer, please try again."

  return {"prompt": request.prompt, "prediction": prediction_text}


if __name__ == "__main__":
  server_port = int(os.environ.get("PORT", 8080))
  uvicorn.run("main:app", host="0.0.0.0", port=server_port, log_level="info")
