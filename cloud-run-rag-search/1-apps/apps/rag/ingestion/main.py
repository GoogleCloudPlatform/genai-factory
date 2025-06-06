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

from google.cloud import bigquery
from vertexai.language_models import TextEmbeddingModel
from google.cloud import aiplatform  # For aiplatform.init()

from src import config
from src import db as database

try:
    BQ_TEXT_COLUMNS = [
        col.strip() for col in config.BQ_TEXT_COLUMNS_STR.split(',')
        if col.strip()
    ]
    TARGET_BQ_COLUMNS = [  # This list is used for metadata extraction
        col.strip() for col in config.TARGET_BQ_COLUMNS_DEFAULT if col.strip()
    ]
    ALL_BQ_COLUMNS_TO_FETCH = []
    _seen_in_all_bq_columns = set()

    # Add columns from TARGET_BQ_COLUMNS first, maintaining their order
    for col in TARGET_BQ_COLUMNS:
        if col not in _seen_in_all_bq_columns:
            ALL_BQ_COLUMNS_TO_FETCH.append(col)
            _seen_in_all_bq_columns.add(col)
    # Then, add any additional columns from BQ_TEXT_COLUMNS, maintaining their order
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
        f"Error parsing numeric environment variable (e.g., DB_PORT, BATCH_SIZE_*, EMBEDDING_DIMENSIONS): {e}"
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
except Exception as e:
    logger.error(f"Error initializing BigQuery client: {e}")
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


def run_indexer():
    """Fetches data from BigQuery, generates embeddings, and stores in Cloud SQL."""
    logger.info("Starting indexer job...")
    logger.info(f"Project ID: {config.PROJECT_ID}, Region: {config.REGION}")
    logger.info(f"BigQuery source: {config.BQ_DATASET}.{config.BQ_TABLE}")
    logger.info(
        f"Columns to fetch from BQ (and use for 'content_to_embed' in order): {', '.join(ALL_BQ_COLUMNS_TO_FETCH)}"
    )
    logger.info(
        f"Subset of columns for direct DB storage (metadata from TARGET_BQ_COLUMNS_DEFAULT): {', '.join(TARGET_BQ_COLUMNS)}"
    )
    logger.info(
        f"Cloud SQL target: {config.DB_HOST}:{config.DB_PORT}/{config.DB_NAME}, table: {config.DB_TABLE}"
    )
    logger.info(
        f"Embedding Model: {config.EMBEDDING_MODEL_NAME} ({config.EMBEDDING_DIMENSIONS} dims)"
    )
    logger.info(
        f"Batch sizes: BQ Page={config.BQ_BATCH_SIZE}, Embedding Request={config.EMBEDDING_BATCH_SIZE}"
    )

    try:
        database.init_db_connection_pool()
        database.create_table_if_not_exists()
    except Exception as e:
        logger.error(f"Halting job due to inability to setup database: {e}")
        sys.exit(1)

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
    total_upserted_count = 0
    batch_for_embedding_processing = []

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

        # 1. Construct 'content_to_embed'
        content_parts = []
        for col_name in ALL_BQ_COLUMNS_TO_FETCH:
            value = row_data.get(col_name)
            formatted_value = format_bq_value_for_embedding(value)
            content_parts.append(f"{col_name}: {formatted_value}")
        current_text_to_embed = "; ".join(content_parts)

        if not current_text_to_embed.strip():
            logger.warning(
                f"Skipping row with ID {item_id_str} due to empty 'content_to_embed'. Original parts: {content_parts}"
            )
            continue

        # 2. Extract Metadata for discrete SQL columns using TARGET_BQ_COLUMNS
        current_metadata_for_sql = {}
        try:
            for target_col in TARGET_BQ_COLUMNS:
                raw_value = row_data.get(target_col)
                if target_col == 'rank':
                    current_metadata_for_sql['rank'] = safe_cast(
                        raw_value, int)
                elif target_col == 'rating':
                    current_metadata_for_sql['rating'] = safe_cast(
                        raw_value, float)
                elif target_col == 'year':
                    current_metadata_for_sql['year'] = safe_cast(
                        raw_value, int)
                    # For text fields, ensure they are strings or None.
                elif target_col in ['title', 'description', 'genre']:
                    current_metadata_for_sql[target_col] = str(
                        raw_value) if raw_value is not None else None
                else:
                    current_metadata_for_sql[target_col] = str(
                        raw_value) if raw_value is not None else None
        except Exception as e:
            logger.warning(
                f"Error processing metadata for ID {item_id_str}. Skipping row. Error: {e}. Row data sample: {dict(list(row_data.items())[:3])}"
            )
            continue

        batch_for_embedding_processing.append({
            "id": item_id_str,
            "text_to_embed": current_text_to_embed,
            "metadata": current_metadata_for_sql,
            "embedding": None
        })

        # 3. Process batch for embeddings when full
        if len(batch_for_embedding_processing) >= config.EMBEDDING_BATCH_SIZE:
            texts_for_api = [
                item["text_to_embed"]
                for item in batch_for_embedding_processing
            ]
            logger.info(
                f"Requesting embeddings for batch of {len(texts_for_api)} texts (Total BQ rows: {processed_bq_rows_count})..."
            )
            embeddings_list_result = get_embeddings_batch_vertexai(
                texts_for_api, config.EMBEDDING_MODEL_NAME)

            if embeddings_list_result and len(embeddings_list_result) == len(
                    batch_for_embedding_processing):
                for i, item in enumerate(batch_for_embedding_processing):
                    item["embedding"] = embeddings_list_result[i]
                upserted_in_batch = database.upsert_batch_to_db(
                    batch_for_embedding_processing)
                total_upserted_count += upserted_in_batch
            else:
                logger.error(
                    f"Failed to get embeddings or length mismatch for batch (ID {batch_for_embedding_processing[0]['id']}). Expected {len(batch_for_embedding_processing)}, got {len(embeddings_list_result) if embeddings_list_result else 'None'}. Skipping DB insert."
                )
            batch_for_embedding_processing = []

        if processed_bq_rows_count % (config.BQ_BATCH_SIZE * 2) == 0:
            logger.info(
                f"Processed {processed_bq_rows_count} BQ rows. Approx {total_upserted_count} records upserted."
            )

    # 4. Process any remaining items in the last batch
    if batch_for_embedding_processing:
        texts_for_api = [
            item["text_to_embed"] for item in batch_for_embedding_processing
        ]
        logger.info(
            f"Requesting embeddings for final batch of {len(texts_for_api)} texts..."
        )
        embeddings_list_result = get_embeddings_batch_vertexai(
            texts_for_api, config.EMBEDDING_MODEL_NAME)

        if embeddings_list_result and len(embeddings_list_result) == len(
                batch_for_embedding_processing):
            for i, item in enumerate(batch_for_embedding_processing):
                item["embedding"] = embeddings_list_result[i]
            upserted_in_batch = database.upsert_batch_to_db(
                batch_for_embedding_processing)
            total_upserted_count += upserted_in_batch
        else:
            logger.error(
                f"Failed to get embeddings or mismatch for final batch (ID {batch_for_embedding_processing[0]['id']}). Skipping DB insert."
            )

    logger.info(
        f"Indexer job finished. Processed {processed_bq_rows_count} rows from BigQuery."
    )
    logger.info(
        f"Total records attempted for upsert into Cloud SQL table '{config.DB_TABLE}': {total_upserted_count}."
    )

    database.dispose_db_pool(
    )  # Dispose pool at the end of successful run or before exit


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
        database.dispose_db_pool()
        sys.exit(e.code)
    except Exception as e:
        logger.exception(
            f"Unhandled error during indexer execution on Task {job_task_index}, Attempt {job_attempt}: {e}"
        )
        database.dispose_db_pool()
        sys.exit(1)
