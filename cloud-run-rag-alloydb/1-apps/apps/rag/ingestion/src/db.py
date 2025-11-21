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

# The AlloyDB Python Connector is the recommended way to connect from apps.
# It handles secure, authorized connections automatically.
from google.cloud.alloydb.connector import Connector

from src import config

# Configure logging
logging.basicConfig(
    level=logging.INFO,  # Set the default logging level
    format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# The SQLAlchemy engine and the database connector are managed globally.
_db_pool: sqlalchemy.engine.Engine | None = None
_connector: Connector | None = None


def init_db_connection_pool():
    """Initializes a connection pool using the Python Connector."""
    global _db_pool, _connector
    if _db_pool:
        logger.info("Connection pool already initialized.")
        return

    # Initialize the database connector
    _connector = Connector(ip_type="PSC")

    # This function will be called by SQLAlchemy to create new connections.
    def getconn():
        # The connector.connect method handles automatically discovering the
        # AlloyDB instance's IP address and securely connecting to it.
        logger.info(f"Creating connector...")

        conn = _connector.connect(
            instance_uri=config.ALLOYDB_INSTANCE_URI,
            driver="pg8000",
            user=config.DB_SA,
            db=config.DB_NAME,
            enable_iam_auth=True,  # Use IAM database authentication
        )

        logging.info("Direct connection to AlloyDB was successful!")

        return conn

    logger.info(
        f"Attempting to connect to AlloyDB instance '{config.ALLOYDB_INSTANCE_URI}' in database '{config.DB_NAME}', user '{config.DB_SA}'"
    )

    try:
        # Create the SQLAlchemy engine using the 'creator' function
        _db_pool = sqlalchemy.create_engine(
            "postgresql+pg8000://",
            creator=getconn,
            pool_size=5,
            max_overflow=2,
            pool_timeout=30,
            pool_recycle=1800,
        )
        # Test the connection
        with _db_pool.connect() as connection:
            logger.info(
                "Successfully connected to the database and obtained a connection from the pool."
            )
    except Exception as e:
        logger.error(f"Error creating the database connection pool: {e}")
        # Clean up the connector and pool on failure
        if _connector:
            _connector.close()
            _connector = None
        _db_pool = None
        raise


def get_db_pool() -> sqlalchemy.engine.Engine:
    """Returns the initialized database connection pool."""
    if not _db_pool:
        errstr = "Database pool not initialized. Cannot provide DB session."
        logger.error(errstr)
        raise ConnectionError(errstr)
    return _db_pool


def dispose_db_pool():
    """Disposes of the database connection pool and the database connector."""
    global _db_pool, _connector
    if _db_pool:
        _db_pool.dispose()
        _db_pool = None
        logger.info("Database connection pool disposed.")
    if _connector:
        _connector.close()
        _connector = None
        logger.info("Database connector closed.")


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
                f"Ensured table '{table_name}' exists with vector extension. PK: '{config.GENERATED_ID_COLUMN_NAME}'"
            )
    except Exception as e:
        logger.error(f"Error creating or verifying table '{table_name}': {e}")
        raise


def upsert_batch_to_db(batch_data: list[dict]) -> int:
    """
    Upserts a batch of data (including embeddings and specific columns) into AlloyDB.
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
        logger.error(f"Error during batch upsert to AlloyDB: {e}")
        if prepared_batch:
            logger.error(
                f"Problematic batch (first generated ID): {prepared_batch[0].get(config.GENERATED_ID_COLUMN_NAME)}"
            )
        return 0
