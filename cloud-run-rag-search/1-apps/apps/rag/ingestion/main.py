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

import os
import logging
import sys
import json
from typing import Any, List, Dict

from vertexai.language_models import TextEmbeddingModel
from google.cloud import aiplatform

from src import config
from src import storage
from src import vector_search

# --- Configuration Loading and Validation ---
try:
    if not config.GCS_SOURCE_BUCKET or not config.GCS_SOURCE_BLOB_NAME:
        raise KeyError(
            "GCS_SOURCE_BUCKET and GCS_SOURCE_BLOB_NAME environment variables must be set."
        )
    if not config.VECTOR_SEARCH_INDEX_NAME:
        raise KeyError(
            "VECTOR_SEARCH_INDEX_NAME environment variable must be set.")

except KeyError as e:
    logging.error(f"Missing required environment variable: {e}")
    sys.exit(1)
except ValueError as e:
    logging.error(
        f"Error parsing numeric environment variable (e.g., BATCH_SIZE_*, EMBEDDING_DIMENSIONS): {e}"
    )
    sys.exit(1)

# --- Logging Setup ---
logging.basicConfig(level=logging.INFO,
                    format='%(name)s - %(levelname)s - %(message)s',
                    handlers=[logging.StreamHandler(sys.stdout)])
logger = logging.getLogger(__name__)

# --- Initialize Vertex AI SDK ---
try:
    aiplatform.init(project=config.PROJECT_ID, location=config.REGION)
    logger.info(
        f"Vertex AI SDK initialized for project {config.PROJECT_ID} in {config.REGION}."
    )
except Exception as e:
    logger.error(f"Error initializing Vertex AI SDK: {e}")
    sys.exit(1)


def format_json_value_for_embedding(value: Any) -> str:
    """
    Formats a JSON value for inclusion in the 'content_to_embed' string.
    """
    if value is None:
        return "None"
    if isinstance(value, list):
        return ",".join(str(v_item).strip() for v_item in value)
    return str(value).strip()


def get_embeddings_batch_vertexai(texts: list[str]) -> list[list[float]]:
    """Gets embeddings for a batch of texts using Vertex AI TextEmbeddingModel."""
    if not texts:
        return []
    try:
        model = TextEmbeddingModel.from_pretrained(config.EMBEDDING_MODEL_NAME)
        response = model.get_embeddings(texts)
        return [embedding.values for embedding in response]
    except Exception as e:
        logger.error(
            f"Error getting embeddings from Vertex AI (model: {config.EMBEDDING_MODEL_NAME}): {e}"
        )
        return []


def create_datapoint(record_id: str, embedding: list[float]) -> dict:
    """
    Creates a simple datapoint dictionary for the Vector Search upsert API,
    containing only the ID and the feature vector.
    """
    return {
        "datapoint_id": record_id,
        "feature_vector": embedding,
    }


def run_indexer():
    """
    Streams data from a GCS JSONL file, generates embeddings, and upserts
    them into a Vertex AI Vector Search index.
    """
    logger.info("Starting indexer job...")
    logger.info(f"Project ID: {config.PROJECT_ID}, Region: {config.REGION}")
    logger.info(
        f"GCS source: gs://{config.GCS_SOURCE_BUCKET}/{config.GCS_SOURCE_BLOB_NAME}"
    )
    logger.info(f"Vector Search Index: {config.VECTOR_SEARCH_INDEX_NAME}")
    logger.info(
        f"Embedding Model: {config.EMBEDDING_MODEL_NAME} ({config.EMBEDDING_DIMENSIONS} dims)"
    )
    logger.info(
        f"Batch sizes: Embedding Request={config.EMBEDDING_BATCH_SIZE}, Vector Search Upsert={config.VECTOR_SEARCH_UPSERT_BATCH_SIZE}"
    )

    batch_for_embedding = []
    batch_for_upsert = []
    total_processed_count = 0
    total_upserted_count = 0

    # Stream the source file line by line
    source_iterator = storage.stream_gcs_jsonl_file(
        project_id=config.PROJECT_ID,
        bucket_name=config.GCS_SOURCE_BUCKET,
        blob_name=config.GCS_SOURCE_BLOB_NAME)

    for record in source_iterator:
        total_processed_count += 1

        # 1. Extract the ID and prepare text for embedding
        record_id = record.get("id")
        if not record_id:
            logger.warning(
                f"Skipping record number {total_processed_count} due to missing 'id' field. Record: {record}"
            )
            continue
        record_id = str(record_id)  # Ensure ID is a string for Vector Search

        content_parts = []
        # Dynamically iterate over all keys in the record, except for 'id'
        for key, value in record.items():
            if key == "id":
                continue
            formatted_value = format_json_value_for_embedding(value)
            content_parts.append(f"{key}: {formatted_value}")

        # Sort parts by key for deterministic embedding generation
        text_to_embed = "; ".join(sorted(content_parts))

        if not text_to_embed.strip():
            logger.warning(
                f"Skipping record with ID {record_id} due to empty content.")
            continue

        batch_for_embedding.append({
            "id": record_id,
            "text_to_embed": text_to_embed
        })

        # 2. Process batch for embeddings when full
        if len(batch_for_embedding) >= config.EMBEDDING_BATCH_SIZE:
            logger.info(
                f"Requesting embeddings for a batch of {len(batch_for_embedding)} records..."
            )
            texts = [item['text_to_embed'] for item in batch_for_embedding]
            embeddings = get_embeddings_batch_vertexai(texts)

            if embeddings and len(embeddings) == len(batch_for_embedding):
                for item, embedding in zip(batch_for_embedding, embeddings):
                    datapoint = create_datapoint(item['id'], embedding)
                    batch_for_upsert.append(datapoint)
            else:
                logger.error("Failed to get embeddings for a batch, skipping.")

            batch_for_embedding = []  # Clear the batch

        # 3. Process batch for Vector Search upsert when full
        if len(batch_for_upsert) >= config.VECTOR_SEARCH_UPSERT_BATCH_SIZE:
            logger.info(
                f"Upserting a batch of {len(batch_for_upsert)} datapoints to Vector Search..."
            )
            vector_search.upsert_datapoints_to_index(
                project=config.PROJECT_ID,
                location=config.REGION,
                index_name=config.VECTOR_SEARCH_INDEX_NAME,
                datapoints=batch_for_upsert)
            total_upserted_count += len(batch_for_upsert)
            batch_for_upsert = []  # Clear the batch

    # Process any remaining items in the embedding batch
    if batch_for_embedding:
        logger.info(
            f"Requesting embeddings for the final batch of {len(batch_for_embedding)} records..."
        )
        texts = [item['text_to_embed'] for item in batch_for_embedding]
        embeddings = get_embeddings_batch_vertexai(texts)
        if embeddings and len(embeddings) == len(batch_for_embedding):
            for item, embedding in zip(batch_for_embedding, embeddings):
                datapoint = create_datapoint(item['id'], embedding)
                batch_for_upsert.append(datapoint)

    # Upsert any remaining datapoints
    if batch_for_upsert:
        logger.info(
            f"Upserting the final batch of {len(batch_for_upsert)} datapoints to Vector Search..."
        )
        vector_search.upsert_datapoints_to_index(
            project=config.PROJECT_ID,
            location=config.REGION,
            index_name=config.VECTOR_SEARCH_INDEX_NAME,
            datapoints=batch_for_upsert)
        total_upserted_count += len(batch_for_upsert)

    logger.info("Indexer job finished.")
    logger.info(
        f"Total records processed from GCS file: {total_processed_count}.")
    logger.info(
        f"Total datapoints successfully upserted to Vector Search: {total_upserted_count}."
    )


if __name__ == "__main__":
    job_task_index = os.environ.get("CLOUD_RUN_TASK_INDEX", "N/A")
    job_attempt = os.environ.get("CLOUD_RUN_TASK_ATTEMPT", "N/A")
    logger.info(
        f"Cloud Run Job: Task Index {job_task_index}, Attempt {job_attempt}.")

    try:
        run_indexer()
        logger.info("Indexer run completed successfully.")
        sys.exit(0)
    except SystemExit as e:
        logger.info(f"Indexer run exited with code {e.code}.")
        sys.exit(e.code)
    except Exception as e:
        logger.exception(
            f"Unhandled error during indexer execution on Task {job_task_index}, Attempt {job_attempt}: {e}"
        )
        sys.exit(1)
