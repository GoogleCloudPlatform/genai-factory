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
import sys

import sqlalchemy
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy import text

from google.cloud.sql.connector import Connector, IPTypes
from src import config


# Configure logging
logging.basicConfig(
    level=logging.INFO, # Set the default logging level
    format='%(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

# Global connector and engine to be initialized at startup
connector: Connector = None
engine: sqlalchemy.engine.Engine = None

def init_db_connection_pool():
    """Initializes the Cloud SQL (PostgreSQL) connector
    and SQLAlchemy engine using IAM authentication."""
    global connector, engine
    if not all([config.DB_HOST, config.DB_NAME, config.DB_PORT, config.DB_SA]):
        logging.warning(
            "Database configuration (DB_HOST, DB_NAME, DB_PORT, DB_SA) "
            "is not complete. Database features will be disabled."
        )
        return
    try:
        connector = Connector()
        db_url = sqlalchemy.engine.url.URL.create(
            drivername="postgresql+pg8000",
            host=config.DB_HOST,
            port=config.DB_PORT,
            username=config.DB_SA,
            database=config.DB_NAME
        )
        engine = sqlalchemy.create_engine(
            db_url,
            pool_size=5,
            max_overflow=2,
            pool_timeout=30,
            pool_recycle=1800
        )
        logging.info("Database connection pool initialized successfully.")
    except Exception as e:
        logging.error(
            f"Failed to initialize database connection pool: {e}",
            exc_info=True
        )
        engine = None # Ensure engine is None if init fails

def get_db_session() -> Session:
    """Dependency to get a database session."""
    if not engine:
        # Raise an error or handle as appropriate
        # if the DB connection is critical
        logging.error("Database engine not initialized. Cannot provide DB session.")
        raise ConnectionError("Database engine not initialized.")
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def search_similar_documents(db: Session, embedding: list[float], top_k: int) -> list[str]:
    """
    Searches for documents with embeddings similar to
    the query_embedding in PostgreSQL using pgvector.
    """
    if not engine:
        logging.warning("Database not configured. Skipping document search.")
        return []

    try:
        embedding_str = str(embedding)

        # Using <=> for cosine distance (pgvector specific).
        # Lower distance = more similar.
        query = text(
            f"""
            SELECT "{config.DB_COLUMN_TEXT}"
            FROM "{config.DB_TABLE}"
            ORDER BY "{config.DB_COLUMN_EMBEDDING}" <=> :embedding
            LIMIT :top_k
            """
        )

        result = db.execute(query, {"embedding": embedding_str, "top_k": top_k})
        documents = [row[0] for row in result.fetchall()]
        logging.info(f"Retrieved {len(documents)} similar documents from DB.")
        return documents
    except sqlalchemy.exc.SQLAlchemyError as e:
        logging.error(f"Database error during similarity search: {e}", exc_info=True)
        return []
    except Exception as e:
        logging.error(f"Unexpected error during similarity search: {e}", exc_info=True)
        return []

def close_db_connection_pool():
    """Closes the Cloud SQL connector and disposes the SQLAlchemy engine."""
    global connector, engine
    if engine:
        engine.dispose()
        logging.info("Database connection pool disposed.")
        engine = None
    if connector:
        connector.close()
        logging.info("Cloud SQL connector closed.")
        connector = None
