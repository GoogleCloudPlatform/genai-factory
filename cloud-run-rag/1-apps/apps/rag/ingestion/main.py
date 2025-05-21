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

import sqlalchemy
from google.cloud import bigquery

from google import genai

import numpy as np
import pg8000

# --- Configuration (Fetch from Environment Variables) ---
try:
    PROJECT_ID = os.environ["PROJECT_ID"]
    REGION = os.environ.get("REGION", "europe-west1")
    BQ_DATASET = os.environ.get("BQ_DATASET", "gf-rrag-0")
    BQ_TABLE = os.environ.get("BQ_TABLE", "gf-rrag-0")

    # --- Columns Configuration ---
    GENERATED_ID_COLUMN_NAME = "id"

    # Columns to concatenate for generating the embedding
    BQ_TEXT_COLUMNS = os.environ.get("BQ_TEXT_COLUMNS", "title,description").split(',')
    BQ_TEXT_COLUMNS = [col.strip() for col in BQ_TEXT_COLUMNS if col.strip()]

    # Define the specific BQ columns we want to fetch and store directly in Cloud SQL
    # Ensure these names match your BigQuery table columns exactly.
    TARGET_BQ_COLUMNS = ['rank', 'title', 'description', 'genre', 'rating', 'year']
    TARGET_BQ_COLUMNS = [col.strip() for col in TARGET_BQ_COLUMNS if col.strip()]

    # Combine all columns needed from BigQuery (excluding the id)
    ALL_BQ_COLUMNS_TO_FETCH = list(set(BQ_TEXT_COLUMNS + TARGET_BQ_COLUMNS))
    if not ALL_BQ_COLUMNS_TO_FETCH:
         logging.error("No columns specified in BQ_TEXT_COLUMNS or TARGET_BQ_COLUMNS. Cannot fetch data.")
         sys.exit(1)
    # --- End Columns Configuration ---

    DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
    DB_PORT = int(os.environ.get("DB_PORT", 5432))
    DB_NAME = os.environ["DB_NAME"]
    DB_SA = os.environ["DB_SA"]
    DB_TABLE = os.environ.get("DB_TABLE", "movie_embeddings")

    MODEL_ID = os.environ.get("MODEL_ID", "text-multilingual-embedding-002")
    BATCH_SIZE_BQ = int(os.environ.get("BATCH_SIZE_BQ", 1000))
    BATCH_SIZE_EMBEDDING = int(os.environ.get("BATCH_SIZE_EMBEDDING", 200))
    EMBEDDING_DIMENSIONS = int(os.environ.get("EMBEDDING_DIMENSIONS", 768))

except KeyError as e:
    logging.error(f"Missing required environment variable: {e}")
    sys.exit(1)
except ValueError as e:
    logging.error(f"Error parsing numeric environment variable (e.g., DB_PORT, BATCH_SIZE_*, EMBEDDING_DIMENSIONS): {e}")
    sys.exit(1)

# --- Logging Setup ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Initialize Clients ---
bq_client = bigquery.Client(project=PROJECT_ID)
vertex_ai_client = genai.Client(vertexai=True, project=PROJECT_ID, location=REGION)

# NOTE: Assuming passwordless connection via Cloud SQL Auth Proxy or similar.
db_url = sqlalchemy.engine.url.URL.create(
    drivername="postgresql+pg8000",
    username=DB_SA,
    host=DB_HOST,
    port=DB_PORT,
    database=DB_NAME,
)
logging.info(f"Connecting to database {DB_HOST}:{DB_PORT}/{DB_NAME} with SA {DB_SA}")
try:
    db_pool = sqlalchemy.create_engine(
        db_url, pool_size=5, max_overflow=2, pool_timeout=30, pool_recycle=1800,
    )
    with db_pool.connect() as connection:
        logging.info("Successfully connected to the database pool.")
except Exception as e:
    logging.error(f"Error creating database connection pool: {e}")
    sys.exit(1)

# --- Helper Functions ---

def safe_cast(value, cast_type, default=None):
    """Safely casts a value to a type, returning default on failure."""
    if value is None:
        return default
    try:
        return cast_type(value)
    except (ValueError, TypeError):
        logging.warning(f"Could not cast '{value}' to {cast_type}. Using default: {default}")
        return default

def create_table_if_not_exists(engine: sqlalchemy.engine.Engine, table_name: str):
    """Creates the target table with specific columns and pgvector, using generated_row_id."""
    # Use the fixed GENERATED_ID_COLUMN_NAME for the primary key (BIGINT)
    # Quote all identifiers to be safe
    create_table_sql = f"""
    CREATE TABLE IF NOT EXISTS "{table_name}" (
        "{GENERATED_ID_COLUMN_NAME}" BIGINT PRIMARY KEY,
        rank INTEGER,
        title TEXT,
        description TEXT,
        genre TEXT,
        rating REAL,
        year INTEGER,
        content_to_embed TEXT,
        embedding vector({EMBEDDING_DIMENSIONS})
    );
    """
    try:
        with engine.connect() as connection:
            with connection.begin(): # Use transaction for DDL
                 connection.execute(sqlalchemy.text(create_table_sql))
            logging.info(f"Ensured table '{table_name}' exists with specified columns (and pgvector). PK: '{GENERATED_ID_COLUMN_NAME}'")
    except Exception as e:
        logging.error(f"Error creating or verifying table '{table_name}': {e}")
        raise

def get_embeddings_batch(texts: list[str]) -> list[list[float]]:
    """Gets embeddings for a batch of texts using Vertex AI."""
    if not texts:
        return []
    try:
        embeddings = vertex_ai_client.models.embed_content(model=MODEL_ID, contents=texts).embeddings

        # Add basic validation
        if not embeddings:
             logging.warning("Received empty embeddings list from Vertex AI.")
             return []
        # Check dimensions of the first embedding only for efficiency
        if embeddings and embeddings[0].values and len(embeddings[0].values) != EMBEDDING_DIMENSIONS:
            logging.error(f"Embedding dimension mismatch! Model '{MODEL_ID}' returned {len(embeddings[0].values)} dimensions, expected {EMBEDDING_DIMENSIONS}. Exiting.")
            sys.exit(1) # Critical error, stop the job
        return [embedding.values for embedding in embeddings]
    except Exception as e:
        logging.error(f"Error getting embeddings from Vertex AI: {e}")
        return [] # Allow job to continue, but log error

def upsert_batch_to_db(engine: sqlalchemy.engine.Engine, batch_data: list[dict]):
    """Upserts a batch of data (including embeddings and specific columns) into Cloud SQL."""
    if not batch_data:
        return 0

    # Define the target columns in the database table, using the generated ID
    # Order matters for the VALUES clause placeholders
    db_columns = [
        GENERATED_ID_COLUMN_NAME, 'rank', 'title', 'description', 'genre', 'rating', 'year',
        'content_to_embed', 'embedding'
    ]
    cols_str = ", ".join([f'"{col}"' for col in db_columns]) # Quote column names
    placeholders = ", ".join([f":{col}" for col in db_columns]) # Placeholders don't need quotes

    # Columns to update on conflict (all except the primary key)
    update_cols = [col for col in db_columns if col != GENERATED_ID_COLUMN_NAME]
    update_statements = [f'"{col}" = EXCLUDED."{col}"' for col in update_cols]
    update_str = ", ".join(update_statements)

    # Use ON CONFLICT for UPSERT (PostgreSQL specific) - Quote identifiers
    # Target the generated ID column for conflict resolution
    upsert_sql = f"""
    INSERT INTO "{DB_TABLE}" ({cols_str})
    VALUES ({placeholders})
    ON CONFLICT ("{GENERATED_ID_COLUMN_NAME}") DO UPDATE
    SET {update_str};
    """

    prepared_batch = []
    for item in batch_data:
        try:
            row_dict = {
                # Use the generated ID (convert item['id'] back to int for BIGINT column)
                GENERATED_ID_COLUMN_NAME: int(item['id']),
                'rank': item['metadata'].get('rank'), # Already cast to int or None
                'title': item['metadata'].get('title'), # String
                'description': item['metadata'].get('description'), # String
                'genre': item['metadata'].get('genre'), # String
                'rating': item['metadata'].get('rating'), # Already cast to float or None
                'year': item['metadata'].get('year'), # Already cast to int or None
                'content_to_embed': item['text_to_embed'], # String
                'embedding': str(item['embedding']) if item.get('embedding') else None, # pgvector string format '[1.2, ...]' or NULL
            }
            # Ensure all keys expected by the SQL placeholders are present, even if None
            for col in db_columns:
                if col not in row_dict:
                    row_dict[col] = None # Should not happen with current logic, but safer

            prepared_batch.append(row_dict)
        except Exception as e:
            logging.error(f"Error preparing row data for DB upsert (ID: {item.get('id', 'N/A')}). Skipping row. Error: {e}. Data: {item}")
            continue # Skip this row, proceed with the rest of the batch

    if not prepared_batch:
        logging.warning("No valid rows prepared for DB upsert in this batch.")
        return 0

    inserted_count = 0
    try:
        with engine.connect() as connection:
            with connection.begin(): # Start transaction
                result = connection.execute(sqlalchemy.text(upsert_sql), prepared_batch)
                # rowcount might be unreliable for multi-row inserts/upserts in some drivers/configs
                inserted_count = len(prepared_batch) # Assume success for all rows in batch if no exception
        logging.info(f"Attempted upsert for {len(prepared_batch)} records into {DB_TABLE}.")
        return len(prepared_batch) # Return number attempted
    except Exception as e:
        logging.error(f"Error during batch upsert to Cloud SQL: {e}")
        logging.error(f"Problematic batch (first generated ID): {prepared_batch[0].get(GENERATED_ID_COLUMN_NAME) if prepared_batch else 'N/A'}")
        # Consider logging the full batch data if feasible and needed for debugging
        return 0 # Indicate failure for this batch

# --- Main Indexing Logic ---
def run_indexer():
    """Fetches data from BigQuery, generates embeddings, and stores in Cloud SQL using ROW_NUMBER() for ID."""
    logging.info("Starting indexer job...")
    logging.info(f"Fetching BQ Columns: {', '.join(ALL_BQ_COLUMNS_TO_FETCH)}")
    logging.info(f"Generating unique ID using ROW_NUMBER() as '{GENERATED_ID_COLUMN_NAME}' (BIGINT PK in DB)")
    logging.info(f"Embedding Text Columns: {', '.join(BQ_TEXT_COLUMNS)}")
    logging.info(f"Target DB Table: {DB_TABLE}")
    logging.info(f"Embedding Model: {MODEL_ID} ({EMBEDDING_DIMENSIONS} dims)")

    try:
        create_table_if_not_exists(db_pool, DB_TABLE)
    except Exception:
        logging.error("Halting job due to inability to setup database table.")
        sys.exit(1)

    # Construct BigQuery query: Select specified columns AND generate a row number
    select_cols_str = ", ".join([f"`{col}`" for col in ALL_BQ_COLUMNS_TO_FETCH])

    # Using ROW_NUMBER() OVER(). No specific order guarantees absolute consistency
    # across runs if underlying table data changes/shuffles without an ORDER BY,
    # but ensures uniqueness within this query execution.
    # Use `ORDER BY (SELECT NULL)` for potentially more stable (but still arbitrary) order in BQ.
    # If a specific, stable order is crucial, add meaningful columns to ORDER BY.
    query = f"""
    SELECT
        ROW_NUMBER() OVER() AS {GENERATED_ID_COLUMN_NAME},
        {select_cols_str}
    FROM
        `{PROJECT_ID}.{BQ_DATASET}.{BQ_TABLE}`
    """

    logging.info(f"Executing BigQuery query")

    try:
        query_job = bq_client.query(query)
        rows_iterator = query_job.result(page_size=BATCH_SIZE_BQ)
    except Exception as e:
        logging.error(f"Error executing BigQuery query: {e}")
        sys.exit(1)

    processed_count = 0
    total_upserted_estimate = 0
    batch_for_embedding = []

    for row in rows_iterator:
        processed_count += 1

        # 1. Extract the Generated Unique ID
        try:
            # The ID is generated by ROW_NUMBER() and aliased
            item_id = str(row[GENERATED_ID_COLUMN_NAME])
            if not item_id: # Should not happen with ROW_NUMBER unless row is None
                 raise ValueError("Generated ID is missing or empty")
        except (KeyError, TypeError, ValueError) as e:
            logging.warning(f"Skipping row number {processed_count}: Cannot find or convert generated ID '{GENERATED_ID_COLUMN_NAME}'. Error: {e}. Row data: {dict(row)}")
            continue

        # 2. Construct Text for Embedding
        text_parts = []
        for col_name_for_embed in BQ_TEXT_COLUMNS:
            # Use row.get() which your debug logs confirmed works correctly.
            value_from_row = row.get(col_name_for_embed)

            if value_from_row is not None:
                # This will append the string value. If value_from_row is an empty string "",
                # it will be appended as such, which matches the intent of your
                # original commented logic: "Current logic appends even if
                # row[col_name_for_embed] is an empty string """
                text_parts.append(str(value_from_row))
            # Optional: Add an else with logging here if you want to know when a BQ_TEXT_COLUMN
            # specifically yields None (either key not found, or value is SQL NULL).
            # else:
            #     if row_num < 3: # To avoid excessive logging
            #         logging.info(f"ID {item_id}: Column '{col_name_for_embed}' from BQ_TEXT_COLUMNS was None or not found using .get(). Skipping for text_parts.")

        text_to_embed = " ".join(text_parts).strip()

        if not text_to_embed:
            logging.warning(f"Skipping row with generated ID {item_id} due to empty text for embedding (from columns: {BQ_TEXT_COLUMNS}).")
            continue

        # 3. Extract Metadata (Specific Columns) with Type Casting
        metadata = {}
        try:
            # Use safe_cast for numeric types
            metadata['rank'] = safe_cast(row.get('rank'), int) if 'rank' in TARGET_BQ_COLUMNS else None
            metadata['rating'] = safe_cast(row.get('rating'), float) if 'rating' in TARGET_BQ_COLUMNS else None
            metadata['year'] = safe_cast(row.get('year'), int) if 'year' in TARGET_BQ_COLUMNS else None
            # Text fields (handle None but keep as string)
            metadata['title'] = str(row.get('title')) if row.get('title') is not None and 'title' in TARGET_BQ_COLUMNS else None
            metadata['description'] = str(row.get('description')) if row.get('description') is not None and 'description' in TARGET_BQ_COLUMNS else None
            metadata['genre'] = str(row.get('genre')) if row.get('genre') is not None and 'genre' in TARGET_BQ_COLUMNS else None

            # Only include keys that are actually in TARGET_BQ_COLUMNS to avoid None pollution
            metadata = {k: v for k, v in metadata.items() if k in TARGET_BQ_COLUMNS}

        except Exception as e:
             logging.warning(f"Error processing metadata for generated ID {item_id}. Skipping row. Error: {e}. Row data: {dict(row)}")
             continue

        batch_for_embedding.append({
            "id": item_id, # Store the generated ID (as string for now)
            "text_to_embed": text_to_embed,
            "metadata": metadata,
            "embedding": None # Placeholder for embedding
        })

        # 4. Process batch when full
        if len(batch_for_embedding) >= BATCH_SIZE_EMBEDDING:
            logging.info(f"Processing embedding batch of size {len(batch_for_embedding)}...")
            texts = [item["text_to_embed"] for item in batch_for_embedding]
            embeddings = get_embeddings_batch(texts)

            if embeddings and len(embeddings) == len(batch_for_embedding):
                for i, item in enumerate(batch_for_embedding):
                    item["embedding"] = embeddings[i]
                total_upserted_estimate += upsert_batch_to_db(db_pool, batch_for_embedding)
            else:
                logging.error(f"Failed to get embeddings or mismatch for batch starting with generated ID {batch_for_embedding[0]['id']}. Skipping DB insert for this batch.")

            batch_for_embedding = [] # Clear batch

        if processed_count % (BATCH_SIZE_BQ * 5) == 0: # Log progress less frequently
             logging.info(f"Processed {processed_count} rows from BigQuery...")

    # 5. Process any remaining items in the last batch
    if batch_for_embedding:
        logging.info(f"Processing final embedding batch of size {len(batch_for_embedding)}...")
        texts = [item["text_to_embed"] for item in batch_for_embedding]
        embeddings = get_embeddings_batch(texts)

        if embeddings and len(embeddings) == len(batch_for_embedding):
            for i, item in enumerate(batch_for_embedding):
                item["embedding"] = embeddings[i]
            total_upserted_estimate += upsert_batch_to_db(db_pool, batch_for_embedding)
        else:
             logging.error(f"Failed to get embeddings or mismatch for final batch starting with generated ID {batch_for_embedding[0]['id']}. Skipping DB insert for this batch.")

    logging.info(f"Indexer job finished. Processed {processed_count} rows from BigQuery.")
    logging.info(f"Attempted to upsert approx {total_upserted_estimate} records into Cloud SQL table '{DB_TABLE}'. Check logs for any batch errors.")

    if db_pool:
        db_pool.dispose()
        logging.info("Database connection pool disposed.")

if __name__ == "__main__":
    try:
        run_indexer()
        sys.exit(0)
    except SystemExit as e:
        sys.exit(e.code)
    except Exception as e:
        logging.exception(f"Unhandled error during indexer execution: {e}")
        sys.exit(1)
