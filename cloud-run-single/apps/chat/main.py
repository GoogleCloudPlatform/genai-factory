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
from fastapi import FastAPI
import google.api_core.exceptions as exceptions
from google.cloud import aiplatform
import google.cloud.logging

from vertexai.generative_models import (
    GenerationConfig,
    GenerativeModel,
)
import uvicorn
import config
from request_model import Prompt


app = FastAPI(title=__name__)


# Configure logging
client = google.cloud.logging.Client()
client.setup_logging()

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
handler = google.cloud.logging.handlers.CloudLoggingHandler(client=client)
logger.addHandler(handler)


logger.info(
    "Initializing Vertex AI client for project=%s, region=%s",
    config.PROJECT_ID,
    config.REGION,
)

aiplatform.init(project=config.PROJECT_ID, location=config.REGION)
logger.info("Vertex AI client initialized successfully.")
model = GenerativeModel(config.MODEL_NAME)
logger.info("Loaded Vertex AI model: %s", config.MODEL_NAME)
parameters = GenerationConfig(
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

    prompt_text = request.prompt
    logger.info("Received prediction request with prompt: '%s...'", prompt_text[:50])

    try:
        response = model.generate_content(prompt_text, generation_config=parameters)

        # --- Process Response ---
        prediction_text = (
            response.text
        )  # Adapt based on the exact model/response structure
        logger.info(
            "Successfully received prediction from Vertex AI: %s",
            prediction_text,
        )

    except exceptions.GoogleAPIError as e:
        logger.error("Vertex AI API call failed: %s", e, exc_info=True)
        # Provide more specific error details if possible
        prediction_text = "Failed to get an answer, please try again."

    return {"prompt": prompt_text, "prediction": prediction_text}


if __name__ == "__main__":
    server_port = int(os.environ.get("PORT", 8080))
    uvicorn.run("main:app", host="0.0.0.0", port=server_port, log_level="info")
