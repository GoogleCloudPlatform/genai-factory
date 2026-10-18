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
import sys

from fastapi import FastAPI, HTTPException
import google.api_core.exceptions as exceptions
from google import genai
from google.genai import types
import uvicorn

from src import config, vector_search
from src.request_model import Prompt

app = FastAPI(title=__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)

logging.info(
    "Initializing Google GenAI client for project=%s, region=%s, location=%s",
    config.PROJECT_ID,
    config.REGION,
    config.GOOGLE_CLOUD_LOCATION,
)
try:
  genai_client = genai.Client(
      vertexai=True,
      project=config.PROJECT_ID,
      location=config.GOOGLE_CLOUD_LOCATION,
  )
  logging.info("Vertex AI client initialized successfully.")
except Exception as e:
  logging.error(f"Failed to initialize GenAI client: {e}", exc_info=True)
  genai_client = None

MODEL_NAME = config.LLM_MODEL_NAME
MODEL_CONFIG = types.GenerateContentConfig(
    temperature=config.LLM_TEMPERATURE,
    top_p=config.LLM_TOP_P,
    top_k=config.LLM_TOP_K,
    candidate_count=config.LLM_CANDIDATE_COUNT,
    max_output_tokens=config.LLM_MAX_OUTPUT_TOKENS,
    thinking_config=types.ThinkingConfig(
        thinking_level=config.LLM_THINKING_LEVEL),
)


@app.on_event("startup")
async def startup_event() -> None:
  logging.info("Application startup...")
  if not genai_client:
    logging.error("GenAI client is not available. Predictions will fail.")


@app.on_event("shutdown")
async def shutdown_event() -> None:
  logging.info("Application shutdown...")


@app.get("/")
async def root() -> dict[str, str | None]:
  """Basic health check / info endpoint."""
  vs_status = ("configured"
               if config.VECTOR_SEARCH_COLLECTION_ID else "not configured")
  client_status = "initialized" if genai_client else "initialization failed"

  return {
      "message": "Vertex AI RAG Sample App (Vector Search 2.0) is running.",
      "project_id": config.PROJECT_ID,
      "region": config.REGION,
      "generative_model_id": config.LLM_MODEL_NAME,
      "vector_search_collection_id": config.VECTOR_SEARCH_COLLECTION_ID,
      "genai_client_status": client_status,
      "vector_search_status": vs_status,
  }


@app.post("/predict")
async def predict_route(request: Prompt) -> dict[str, str]:
  """Endpoint to make a prediction using Vertex AI, augmented with context from Vector Search 2.0."""

  if not genai_client:
    logging.error("GenAI client not initialized.")
    raise HTTPException(status_code=503, detail="GenAI client not available.")

  logging.info("Received prediction request with prompt: '%s...'",
               request.prompt[:100])

  context_str = ""
  augmented_prompt = request.prompt

  rag_is_configured = all([
      config.PROJECT_ID,
      config.REGION,
      config.VECTOR_SEARCH_COLLECTION_ID,
  ])

  if rag_is_configured:
    try:
      similar_docs_content = vector_search.search_similar_documents(
          request.prompt, config.RETRIEVER_TOP_K)
      if similar_docs_content:
        context_str = "\n\n".join(similar_docs_content)
        augmented_prompt = (
            f"Based on the following context, answer the question.\n\n"
            f"Context:\n{context_str}\n\n"
            f"Question: {request.prompt}")
        logging.info(
            "Augmented prompt with %d documents from Vector Search 2.0.",
            len(similar_docs_content),
        )
      else:
        logging.info(
            "No relevant documents found in Vector Search 2.0, using original prompt."
        )
    except exceptions.GoogleAPIError as e:
      logging.error(f"Failed to search Vector Search 2.0 collection: {e}",
                    exc_info=True)
    except Exception as e:
      logging.error(f"Unexpected error in RAG pipeline: {e}", exc_info=True)
  else:
    logging.warning("RAG retrieval is not configured, using original prompt.")

  try:
    response = genai_client.models.generate_content(
        model=MODEL_NAME,
        contents=[augmented_prompt],
        config=MODEL_CONFIG,
    )

    prediction_text = ""
    if (response.candidates and response.candidates[0].content and
        response.candidates[0].content.parts):
      prediction_text = "".join(part.text
                                for part in response.candidates[0].content.parts
                                if hasattr(part, "text") and part.text)

    if not prediction_text:
      logging.warning("Received an empty prediction from Vertex AI.")
      prediction_text = "I could not generate a response based on the input."

    logging.info(
        "Successfully received prediction from Vertex AI: %s...",
        prediction_text[:100],
    )

  except exceptions.GoogleAPIError as e:
    logging.error(f"Vertex AI API call failed: {e}", exc_info=True)
    prediction_text = f"Failed to get an answer from the model: {e}"
  except Exception as e:
    logging.error(f"Unexpected error during model generation: {e}",
                  exc_info=True)
    prediction_text = (
        "An unexpected error occurred while trying to get an answer.")

  return {
      "prompt": request.prompt,
      "augmented_prompt": augmented_prompt if context_str else request.prompt,
      "retrieved_context": context_str,
      "prediction": prediction_text,
  }


if __name__ == "__main__":
  server_port = int(os.environ.get("PORT", 8080))
  uvicorn.run("main:app", host="0.0.0.0", port=server_port, log_level="info")
