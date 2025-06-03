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
import sqlalchemy

from src import config

logger = logging.getLogger(__name__)

_db_pool: sqlalchemy.engine.Engine | None = None


def init_db_connection_pool():
    """Initializes the database connection pool."""
    global _db_pool
    if _db_pool:
        logger.info("Database connection pool already initialized.")
        return

    db_port_val = getattr(config, 'DB_PORT', 5432)
    if isinstance(db_port_val, str):
        try:
            db_port_val = int(db_port_val)
        except ValueError:
            logger.error(
                f"Invalid DB_PORT value: {db_port_val}. Must be an integer.")
            raise ValueError(f"Invalid DB_PORT value: {db_port_val}")

    db_url = sqlalchemy.engine.url.URL.create(
        drivername="postgresql+pg8000",
        username=config.DB_SA,
        host=config.DB_HOST,
        port=db_port_val,
        database=config.DB_NAME,
    )
    logger.info(
        f"Attempting to connect to database: {config.DB_NAME} on {config.DB_HOST}:{db_port_val} with user {config.DB_SA}"
    )
    try:
        _db_pool = sqlalchemy.create_engine(db_url,
                                            pool_size=5,
                                            max_overflow=2,
                                            pool_timeout=30,
                                            pool_recycle=1800)
        with _db_pool.connect() as connection:
            logger.info(
                "Successfully connected to the database and obtained a connection from the pool."
            )
    except Exception as e:
        logger.error(
            f"Error creating database connection pool or testing connection: {e}"
        )
        _db_pool = None
        raise


def get_db_pool() -> sqlalchemy.engine.Engine:
    """Returns the initialized database connection pool."""
    if not _db_pool:
        raise ConnectionError(
            "Database pool not initialized. Call init_db_connection_pool() first."
        )
    return _db_pool


def dispose_db_pool():
    """Disposes of the database connection pool."""
    global _db_pool
    if _db_pool:
        _db_pool.dispose()
        _db_pool = None
        logger.info("Database connection pool disposed.")


def create_table_if_not_exists():
    """Creates the target table with specific columns and pgvector if it doesn't exist."""
    engine = get_db_pool()
    table_name = config.DB_TABLE

    create_table_sql = f"""
    CREATE TABLE IF NOT EXISTS "{table_name}" (
        "{config.GENERATED_ID_COLUMN_NAME}" BIGINT PRIMARY KEY,
        rank INTEGER,
        title TEXT,
        description TEXT,
        genre TEXT,
        rating REAL,
        year INTEGER,
        content_to_embed TEXT,
        embedding vector({config.EMBEDDING_DIMENSIONS})
    );
    GRANT SELECT ON TABLE "{table_name}" TO PUBLIC;
    """
    try:
        with engine.connect() as connection:
            with connection.begin():  # Use transaction
                connection.execute(
                    sqlalchemy.text("CREATE EXTENSION IF NOT EXISTS vector;"))
                connection.execute(sqlalchemy.text(create_table_sql))
            logger.info(
                f"Ensured table '{table_name}' exists with pgvector. PK: '{config.GENERATED_ID_COLUMN_NAME}'"
            )
    except Exception as e:
        logger.error(f"Error creating or verifying table '{table_name}': {e}")
        raise


def upsert_batch_to_db(batch_data: list[dict]) -> int:
    """
    Upserts a batch of data (including embeddings and specific columns) into Cloud SQL.
    The `batch_data` items should have an 'id', 'text_to_embed', 'embedding',
    and a 'metadata' dictionary containing keys like 'rank', 'title', etc.
    """
    engine = get_db_pool()
    if not batch_data:
        return 0

    db_columns = [
        config.GENERATED_ID_COLUMN_NAME, 'rank', 'title', 'description',
        'genre', 'rating', 'year', 'content_to_embed', 'embedding'
    ]
    cols_str = ", ".join([f'"{col}"' for col in db_columns])
    placeholders = ", ".join([f":{col}" for col in db_columns])
    update_cols = [
        col for col in db_columns if col != config.GENERATED_ID_COLUMN_NAME
    ]
    update_statements = [f'"{col}" = EXCLUDED."{col}"' for col in update_cols]
    update_str = ", ".join(update_statements)

    upsert_sql_stmt = sqlalchemy.text(f"""
    INSERT INTO "{config.DB_TABLE}" ({cols_str})
    VALUES ({placeholders})
    ON CONFLICT ("{config.GENERATED_ID_COLUMN_NAME}") DO UPDATE
    SET {update_str};
    """)

    prepared_batch = []
    for item in batch_data:
        try:
            row_dict = {
                col: None
                for col in db_columns
            }  # Initialize all DB keys
            row_dict.update({
                config.GENERATED_ID_COLUMN_NAME:
                int(item['id']),
                'content_to_embed':
                item['text_to_embed'],
                'embedding':
                str(item['embedding']) if item.get('embedding') else None,
            })

            if 'metadata' in item and isinstance(item['metadata'], dict):
                for key, value in item['metadata'].items():
                    if key in row_dict:
                        row_dict[key] = value
            else:
                logger.warning(
                    f"Missing or invalid 'metadata' in item with ID {item.get('id', 'N/A')}. Expected a dict."
                )

            prepared_batch.append(row_dict)
        except Exception as e:
            logger.error(
                f"Error preparing row data for DB upsert (ID: {item.get('id', 'N/A')}). Skipping row. Error: {e}. Data text_to_embed[:50]='{str(item.get('text_to_embed'))[:50]}'"
            )
            continue

    if not prepared_batch:
        logger.warning("No valid rows prepared for DB upsert in this batch.")
        return 0

    try:
        with engine.connect() as connection:
            with connection.begin():
                connection.execute(upsert_sql_stmt, prepared_batch)
        logger.info(
            f"Successfully attempted upsert for {len(prepared_batch)} records into {config.DB_TABLE}."
        )
        return len(prepared_batch)
    except Exception as e:
        logger.error(f"Error during batch upsert to Cloud SQL: {e}")
        if prepared_batch:
            logger.error(
                f"Problematic batch (first generated ID): {prepared_batch[0].get(config.GENERATED_ID_COLUMN_NAME)}"
            )
        return 0
