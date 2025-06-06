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
import sys

from fastapi import FastAPI, HTTPException, Depends

import google.api_core.exceptions as exceptions
from google import genai
from google.genai import types
import google.cloud.logging

from sqlalchemy.orm import Session

import uvicorn

from src import config
from src.request_model import Prompt
from src import db as database

app = FastAPI(title=__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,  # Set the default logging level
    format='%(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)])

logging.info("Initializing Google GenAI client for project=%s, region=%s",
             config.PROJECT_ID, config.REGION)
try:
    genai_client = genai.Client(vertexai=True,
                                project=config.PROJECT_ID,
                                location=config.REGION)
    logging.info("Vertex AI client initialized successfully.")
except Exception as e:
    logging.error(f"Failed to initialize GenAI client: {e}", exc_info=True)
    genai_client = None

MODEL_NAME = config.MODEL_NAME
MODEL_CONFIG = types.GenerateContentConfig(
    temperature=config.TEMPERATURE,
    top_p=config.TOP_P,
    top_k=config.TOP_K,
    candidate_count=config.CANDIDATE_COUNT,
    max_output_tokens=config.MAX_OUTPUT_TOKENS,
)


@app.on_event("startup")
async def startup_event():
    logging.info("Application startup...")
    database.init_db_connection_pool()
    if not genai_client:
        logging.error("GenAI client is not available. Predictions will fail.")


@app.on_event("shutdown")
async def shutdown_event():
    logging.info("Application shutdown...")
    database.close_db_connection_pool()


@app.get("/")
async def root():
    """Basic health check / info endpoint."""
    db_status = "connected (IAM Auth)" if database.engine else "not connected/configured"
    client_status = "initialized" if genai_client else "initialization failed"
    return {
        "message":
        "Vertex AI RAG Sample App (PostgreSQL with IAM Auth) is running.",
        "project_id": config.PROJECT_ID,
        "region": config.REGION,
        "generative_model_id": config.MODEL_NAME,
        "embedding_model_id": config.EMBEDDING_MODEL_NAME,
        "genai_client_status": client_status,
        "database_status": db_status,
    }


@app.post("/predict")
async def predict_route(request: Prompt,
                        db: Session = Depends(database.get_db_session)):
    """Endpoint to make a prediction using Vertex AI, augmented with context from Cloud SQL."""

    if not genai_client:
        logging.error("GenAI client not initialized.")
        raise HTTPException(status_code=503,
                            detail="GenAI client not available.")
    if config.MODEL_NAME is None or MODEL_CONFIG is None:
        logging.error("Vertex AI model or config not initialized.")
        raise HTTPException(
            status_code=500,
            detail="Internal server error: Model or config not initialized.")

    logging.info("Received prediction request with prompt: '%s...'",
                 request.prompt[:100])

    context_str = ""
    augmented_prompt = request.prompt

    if database.engine:
        try:
            logging.info(
                f"Generating embedding for prompt using model: {config.EMBEDDING_MODEL_NAME}"
            )
            embedding_response = genai_client.models.embed_content(
                model=config.EMBEDDING_MODEL_NAME,
                contents=[request.prompt]).embeddings[0].values

            logging.info(
                f"Generated query embedding (first 3 dimensions): {embedding_response[:3]}..."
            )

            similar_docs = database.search_similar_documents(
                db, embedding_response, config.TOP_K)

            if similar_docs:
                context_str = "\n\n".join(similar_docs)
                augmented_prompt = (
                    f"Based on the following context, answer the question.\n\n"
                    f"Context:\n{context_str}\n\n"
                    f"Question: {request.prompt}")
                logging.info("Augmented prompt with context from database.")
            else:
                logging.info(
                    "No relevant documents found in database, using original prompt."
                )

        except exceptions.GoogleAPIError as e:
            logging.error(
                f"Failed to generate embedding or search database: {e}",
                exc_info=True)
        except ConnectionError as e:
            logging.error(f"Database connection error: {e}", exc_info=True)
        except Exception as e:
            logging.error(f"Unexpected error in RAG pipeline: {e}",
                          exc_info=True)

    try:
        response = genai_client.models.generate_content(
            model=MODEL_NAME,
            contents=[augmented_prompt],
            config=MODEL_CONFIG,
        )

        prediction_text = ""
        if response.candidates:
            if response.candidates[0].content and response.candidates[
                    0].content.parts:
                prediction_text = "".join(
                    part.text for part in response.candidates[0].content.parts
                    if hasattr(part, 'text'))

        if not prediction_text and hasattr(response, 'text'):
            prediction_text = response.text

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
        prediction_text = "An unexpected error occurred while trying to get an answer."

    return {
        "prompt": request.prompt,
        "augmented_prompt":
        augmented_prompt if context_str else request.prompt,
        "retrieved_context": context_str,
        "prediction": prediction_text
    }


if __name__ == "__main__":
    server_port = int(os.environ.get("PORT", 8080))
    # uvicorn.run("main:app", host="0.0.0.0", port=server_port, log_level="info", reload=True) # For local dev
    uvicorn.run("main:app", host="0.0.0.0", port=server_port, log_level="info")
