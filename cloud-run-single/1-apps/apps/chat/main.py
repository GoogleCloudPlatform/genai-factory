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

import logging
import os
from fastapi import FastAPI, HTTPException
import google.api_core.exceptions as exceptions
from google import genai
from google.genai import types
import google.cloud.logging

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
    "Initializing Google GenAI client for project=%s, region=%s",
    config.PROJECT_ID,
    config.REGION,
)
genai_client = genai.Client(vertexai=True,
                            project=config.PROJECT_ID,
                            location=config.REGION)
logger.info("Vertex AI client initialized successfully.")

MODEL_NAME = config.MODEL_NAME
MODEL_CONFIG = types.GenerateContentConfig(
    temperature=config.TEMPERATURE,
    top_p=config.TOP_P,
    top_k=config.TOP_K,
    candidate_count=config.CANDIDATE_COUNT,
    max_output_tokens=config.MAX_OUTPUT_TOKENS,
)


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
        raise HTTPException(
            status_code=500,
            detail="Internal server error: Model not initialized.")

    logger.info("Received prediction request with prompt: '%s...'",
                request.prompt[:100])

    try:
        response = genai_client.models.generate_content(
            model=MODEL_NAME,
            contents=request.prompt,
            config=MODEL_CONFIG,
        )

        # --- Process Response ---
        prediction_text = response.text
        logger.info(
            "Successfully received prediction from Vertex AI: %s",
            prediction_text[:100],
        )

    except exceptions.GoogleAPIError as e:
        logger.error("Vertex AI API call failed: %s", e, exc_info=True)
        prediction_text = "Failed to get an answer, please try again."

    return {"prompt": request.prompt, "prediction": prediction_text}


if __name__ == "__main__":
    server_port = int(os.environ.get("PORT", 8080))
    uvicorn.run("main:app", host="0.0.0.0", port=server_port, log_level="info")
