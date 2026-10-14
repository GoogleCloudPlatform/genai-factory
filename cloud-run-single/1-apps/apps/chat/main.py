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
from fastapi import FastAPI, HTTPException
from google.api_core.client_options import ClientOptions
import google.api_core.exceptions as exceptions
from google import genai
from google.genai import types
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
    "Initializing Google GenAI client for project=%s, location=%s",
    config.PROJECT_ID,
    config.GOOGLE_CLOUD_LOCATION,
)
genai_client = genai.Client(vertexai=True, project=config.PROJECT_ID,
                            location=config.GOOGLE_CLOUD_LOCATION)
logger.info("Google GenAI client initialized successfully.")
logger.debug("Model armor template: %s", config.MODEL_ARMOR_TEMPLATE)

model_armor_client = modelarmor_v1.ModelArmorClient(
    transport="rest",
    client_options=ClientOptions(
        api_endpoint=f"modelarmor.{config.REGION}.rep.googleapis.com"),
)

MODEL_NAME = config.MODEL_NAME
MODEL_CONFIG = types.GenerateContentConfig(
    temperature=config.TEMPERATURE,
    top_p=config.TOP_P,
    top_k=config.TOP_K,
    candidate_count=config.CANDIDATE_COUNT,
    max_output_tokens=config.MAX_OUTPUT_TOKENS,
    thinking_config=types.ThinkingConfig(thinking_level=config.THINKING_LEVEL),
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


@app.get("/")
async def root():
  """Basic health check / info endpoint."""

  return {
      "message": "Vertex AI ADC Sample App is running.",
      "project_id": config.PROJECT_ID,
      "region": config.REGION,
      "model_endpoint_id": config.MODEL_NAME,
  }


@app.post("/predict")
async def predict_route(request: Prompt):
  """Endpoint to make a prediction using Vertex AI."""

  if MODEL_NAME is None or MODEL_CONFIG is None:
    logger.error("Vertex AI model not initialized.")
    raise HTTPException(status_code=500,
                        detail="Internal server error: Model not initialized.")

  logger.debug("Received prediction request with prompt: '%s...'",
               request.prompt[:100])

  try:
    if _is_blocked_by_model_armor(request.prompt):
      logger.warning("User prompt was blocked by Model Armor.")
      return {
          "prompt": request.prompt,
          "prediction": "Prompt was blocked by Model Armor.",
      }

    response = genai_client.models.generate_content(
        model=MODEL_NAME,
        contents=request.prompt,
        config=MODEL_CONFIG,
    )

    # --- Process Response ---
    prediction_text = response.text
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

  except exceptions.GoogleAPIError as e:
    logger.error("Vertex AI API call failed: %s", e, exc_info=True)
    prediction_text = "Failed to get an answer, please try again."

  return {"prompt": request.prompt, "prediction": prediction_text}


if __name__ == "__main__":
  server_port = int(os.environ.get("PORT", 8080))
  uvicorn.run("main:app", host="0.0.0.0", port=server_port, log_level="info")
