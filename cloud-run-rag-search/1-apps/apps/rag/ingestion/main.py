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
import tempfile
from typing import Optional

from google.cloud import bigquery
from google.cloud import storage as gcs_storage
from vertexai.language_models import TextEmbeddingModel
from google.cloud import aiplatform

from src import config
from src import storage
from src import vector_search

try:
    if not config.GCS_BUCKET:
        raise KeyError(
            "GCS_BUCKET environment variable must be set."
        )

    BQ_TEXT_COLUMNS = [
        col.strip() for col in config.BQ_TEXT_COLUMNS_STR.split(',')
        if col.strip()
    ]
    TARGET_BQ_COLUMNS = [
        col.strip() for col in config.TARGET_BQ_COLUMNS_DEFAULT if col.strip()
    ]
    ALL_BQ_COLUMNS_TO_FETCH = []
    _seen_in_all_bq_columns = set()

    for col in TARGET_BQ_COLUMNS:
        if col not in _seen_in_all_bq_columns:
            ALL_BQ_COLUMNS_TO_FETCH.append(col)
            _seen_in_all_bq_columns.add(col)

    for col in BQ_TEXT_COLUMNS:
        if col not in _seen_in_all_bq_columns:
            ALL_BQ_COLUMNS_TO_FETCH.append(col)
            _seen_in_all_bq_columns.add(col)

    if not ALL_BQ_COLUMNS_TO_FETCH:
        logging.error(
            "No columns specified to fetch from BigQuery (derived from TARGET_BQ_COLUMNS and BQ_TEXT_COLUMNS). Cannot proceed."
        )
        sys.exit(1)

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

# --- Initialize Clients ---
try:
    bq_client = bigquery.Client(project=config.PROJECT_ID)
    logger.info("BigQuery client initialized.")
    # The storage client is initialized within the upload function,
    # but we can initialize it here to fail early if auth is wrong.
    gcs_storage.Client(project=config.PROJECT_ID)
    logger.info("Google Cloud Storage client initialized successfully.")
except Exception as e:
    logger.error(f"Error initializing Google Cloud client: {e}")
    sys.exit(1)

try:
    aiplatform.init(project=config.PROJECT_ID, location=config.REGION)
    logger.info(
        f"Vertex AI SDK initialized for project {config.PROJECT_ID} in {config.REGION}."
    )
except Exception as e:
    logger.error(f"Error initializing Vertex AI SDK: {e}")
    sys.exit(1)


def format_bq_value_for_embedding(value) -> str:
    """
    Formats a BigQuery value for inclusion in
    the 'content_to_embed' string.
    """
    if value is None:
        return "None"  # Represent SQL NULL as the string "None"
    if isinstance(value, list):  # For ARRAY types from BigQuery
        return ",".join(str(v_item).strip() for v_item in value)
    if isinstance(value, bool):
        return str(value)  # "True" or "False"
    return str(value).strip()


def safe_cast(value, cast_type, default=None):
    """Safely casts a value to a type, returning default on failure."""
    if value is None:
        return default
    try:
        return cast_type(value)
    except (ValueError, TypeError):
        logger.warning(
            f"Could not cast '{value}' to {cast_type}. Using default: {default}"
        )
        return default


def get_embeddings_batch_vertexai(texts: list[str],
                                  model_id_name: str) -> list[list[float]]:
    """Gets embeddings for a batch of texts using Vertex AI TextEmbeddingModel."""
    if not texts:
        return []
    try:
        model = TextEmbeddingModel.from_pretrained(model_id_name)
        response = model.get_embeddings(
            texts)  # Max batch size is 250 for many models
        embeddings_values = [embedding.values for embedding in response]

        if not embeddings_values:
            logger.warning(
                f"Received empty embeddings list from Vertex AI model '{model_id_name}'."
            )
            return []
        if embeddings_values[0] and len(
                embeddings_values[0]) != config.EMBEDDING_DIMENSIONS:
            logger.error(
                f"Embedding dimension mismatch! Model '{model_id_name}' returned {len(embeddings_values[0])} dims, expected {config.EMBEDDING_DIMENSIONS}. Exiting."
            )
            sys.exit(1)
        return embeddings_values
    except Exception as e:
        logger.error(
            f"Error getting embeddings from Vertex AI (model: {model_id_name}): {e}"
        )
        return []


def process_and_write_batch(batch_to_process: list[dict], temp_file_handle):
    """
    Gets embeddings for a batch, formats the final JSON, and writes to a file handle.
    Returns the number of records successfully processed and written.
    """
    if not batch_to_process:
        return 0

    texts_for_api = [item["text_to_embed"] for item in batch_to_process]
    logger.info(
        f"Requesting embeddings for batch of {len(texts_for_api)} texts...")

    embeddings_list = get_embeddings_batch_vertexai(texts_for_api,
                                                      config.EMBEDDING_MODEL_NAME)

    if not embeddings_list or len(embeddings_list) != len(batch_to_process):
        logger.error(
            f"Failed to get embeddings or length mismatch for batch starting with ID {batch_to_process[0]['id']}. Expected {len(batch_to_process)}, got {len(embeddings_list) if embeddings_list else 'None'}. Skipping write for this batch."
        )
        return 0

    processed_count = 0
    for i, item in enumerate(batch_to_process):
        output_record = {}
        output_record[config.GENERATED_ID_COLUMN_NAME] = int(item['id'])
        output_record.update(item['metadata'])
        output_record['embedding'] = embeddings_list[i]

        temp_file_handle.write(json.dumps(output_record) + '\n')
        processed_count += 1

    return processed_count


def run_indexer():
    """Fetches data from BigQuery, generates embeddings, stores in GCS, and updates a Vector Search index."""
    logger.info("Starting indexer job...")
    logger.info(f"Project ID: {config.PROJECT_ID}, Region: {config.REGION}")
    logger.info(f"BigQuery source: {config.BQ_DATASET}.{config.BQ_TABLE}")
    logger.info(
        f"Columns to fetch from BQ (and use for 'content_to_embed' in order): {', '.join(ALL_BQ_COLUMNS_TO_FETCH)}"
    )
    logger.info(
        f"Subset of columns for direct JSON storage (metadata from TARGET_BQ_COLUMNS_DEFAULT): {', '.join(TARGET_BQ_COLUMNS)}"
    )
    logger.info(
        f"GCS destination: gs://{config.GCS_BUCKET}/{config.GCS_OUTPUT_FILENAME}"
    )
    logger.info(
        f"Embedding Model: {config.EMBEDDING_MODEL_NAME} ({config.EMBEDDING_DIMENSIONS} dims)"
    )
    logger.info(
        f"Batch sizes: BQ Page={config.BQ_BATCH_SIZE}, Embedding Request={config.EMBEDDING_BATCH_SIZE}"
    )

    select_cols_str = ", ".join(
        [f"`{col}`" for col in ALL_BQ_COLUMNS_TO_FETCH])
    query = f"""
    SELECT
        ROW_NUMBER() OVER() AS {config.GENERATED_ID_COLUMN_NAME},
        {select_cols_str}
    FROM
        `{config.PROJECT_ID}.{config.BQ_DATASET}.{config.BQ_TABLE}`
    """

    logger.info("Executing BigQuery query...")
    try:
        query_job = bq_client.query(query)
        rows_iterator = query_job.result(page_size=config.BQ_BATCH_SIZE)
        logger.info(
            "BigQuery query submitted successfully, iterating results.")
    except Exception as e:
        logger.error(f"Error executing BigQuery query: {e}")
        sys.exit(1)

    processed_bq_rows_count = 0
    total_written_count = 0
    batch_for_embedding_processing = []

    # Use a temporary file to store results incrementally, avoiding high memory usage.
    with tempfile.NamedTemporaryFile(mode='w',
                                     suffix=".json",
                                     delete=True,
                                     encoding='utf-8') as temp_f:
        logger.info(f"Writing intermediate results to temp file: {temp_f.name}")

        for row_idx, row_data in enumerate(rows_iterator):
            processed_bq_rows_count += 1

            try:
                item_id_val = row_data[config.GENERATED_ID_COLUMN_NAME]
                if item_id_val is None:
                    raise ValueError("Generated ID is missing or null")
                item_id_str = str(item_id_val)
            except (KeyError, TypeError, ValueError) as e:
                logger.warning(
                    f"Skipping BQ row number {processed_bq_rows_count} (iterator index {row_idx}): Cannot get generated ID '{config.GENERATED_ID_COLUMN_NAME}'. Error: {e}. Row keys: {list(row_data.keys()) if row_data else 'None'}"
                )
                continue

            content_parts = []
            for col_name in ALL_BQ_COLUMNS_TO_FETCH:
                value = row_data.get(col_name)
                formatted_value = format_bq_value_for_embedding(value)
                content_parts.append(f"{col_name}: {formatted_value}")
            current_text_to_embed = "; ".join(content_parts)

            if not current_text_to_embed.strip():
                logger.warning(
                    f"Skipping row with ID {item_id_str} due to empty 'content_to_embed'."
                )
                continue

            current_metadata_for_json = {}
            try:
                for target_col in TARGET_BQ_COLUMNS:
                    raw_value = row_data.get(target_col)
                    if target_col == 'rank':
                        current_metadata_for_json['rank'] = safe_cast(
                            raw_value, int)
                    elif target_col == 'rating':
                        current_metadata_for_json['rating'] = safe_cast(
                            raw_value, float)
                    elif target_col == 'year':
                        current_metadata_for_json['year'] = safe_cast(
                            raw_value, int)
                    elif target_col in ['title', 'description', 'genre']:
                        current_metadata_for_json[target_col] = str(
                            raw_value) if raw_value is not None else None
                    else:
                        current_metadata_for_json[target_col] = str(
                            raw_value) if raw_value is not None else None
            except Exception as e:
                logger.warning(
                    f"Error processing metadata for ID {item_id_str}. Skipping row. Error: {e}."
                )
                continue

            batch_for_embedding_processing.append({
                "id": item_id_str,
                "text_to_embed": current_text_to_embed,
                "metadata": current_metadata_for_json,
            })

            if len(batch_for_embedding_processing) >= config.EMBEDDING_BATCH_SIZE:
                written_count = process_and_write_batch(
                    batch_for_embedding_processing, temp_f)
                total_written_count += written_count
                batch_for_embedding_processing = []

            if processed_bq_rows_count % (config.BQ_BATCH_SIZE * 2) == 0:
                logger.info(
                    f"Processed {processed_bq_rows_count} BQ rows. Approx {total_written_count} records written to temp file."
                )

        if batch_for_embedding_processing:
            logger.info("Processing final batch of records...")
            written_count = process_and_write_batch(
                batch_for_embedding_processing, temp_f)
            total_written_count += written_count

        logger.info(
            "Finished processing all BQ rows. Now uploading final file to GCS."
        )
        temp_f.flush()

        # --- upload to gcs ---
        storage.upload_file_to_gcs(
            local_file_path=temp_f.name,
            bucket_name=config.GCS_BUCKET,
            destination_blob_name=config.GCS_OUTPUT_FILENAME,
            project_id=config.PROJECT_ID)

        # --- update vector search index ---
        if config.VECTOR_SEARCH_INDEX_NAME:
            gcs_uri_for_update = f"gs://{config.GCS_BUCKET}"
            vector_search.update_index_embeddings(
                project=config.PROJECT_ID,
                location=config.REGION,
                index_name=config.VECTOR_SEARCH_INDEX_NAME,
                gcs_uri=gcs_uri_for_update,
                is_complete_overwrite=config.VECTOR_SEARCH_INDEX_OVERWRITE,
            )
        else:
            logger.info("VECTOR_SEARCH_INDEX_NAME not set. Skipping Vector Search index update.")


    logger.info(
        f"Indexer job finished. Processed {processed_bq_rows_count} rows from BigQuery."
    )
    logger.info(
        f"Total records written to GCS file: {total_written_count}."
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
