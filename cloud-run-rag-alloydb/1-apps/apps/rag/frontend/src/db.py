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
import sys
import sqlalchemy
from sqlalchemy.orm import sessionmaker, Session
from src import config
# The AlloyDB Python Connector is the recommended way to connect from apps.
# It handles secure, authorized connections automatically.
from google.cloud.alloydb.connector import Connector

# Configure logging
logging.basicConfig(
    level=logging.INFO,  # Set the default logging level
    format='%(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)])
logger = logging.getLogger(__name__)

# Global connector and engine to be initialized at startup
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

    #    # The AlloyDB Connector requires ALLOYDB_INSTANCE_URI, DB_NAME, and DB_SA.
    #    if not all([config.ALLOYDB_INSTANCE_URI, config.DB_NAME, config.DB_SA]):
    #        logger.warning(
    #            "AlloyDB configuration (ALLOYDB_INSTANCE_URI, DB_NAME, DB_SA) "
    #            "is not complete. Database features will be disabled.")
    #        return

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
            f"Attempting to connect to AlloyDB instance '{config.ALLOYDB_INSTANCE_URI}' "
            f"in database '{config.DB_NAME}', user '{config.DB_SA}' using IAM auth."
        )

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


def get_db_session() -> Session:
    """Dependency to get a database session."""
    # Raise an error or handle as appropriate
    # if the DB connection is critical
    if not _db_pool:
        logger.error(
            "Database pool not initialized. Cannot provide DB session.")
        raise ConnectionError("Database pool not initialized.")
    SessionLocal = sessionmaker(autocommit=False,
                                autoflush=False,
                                bind=_db_pool)
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def search_similar_documents(db: Session, embedding: list[float],
                             top_k: int) -> list[str]:
    """
    Searches for documents with embeddings similar to
    the query_embedding in PostgreSQL using pgvector.
    """
    if not _db_pool:
        logger.warning("Database not configured. Skipping document search.")
        return []
    try:
        embedding_str = str(embedding)
        # Using <=> for cosine distance (pgvector specific).
        # Lower distance = more similar.
        query = sqlalchemy.text(f"""
            SELECT "{config.DB_COLUMN_TEXT}"
            FROM "{config.DB_TABLE}"
            ORDER BY "{config.DB_COLUMN_EMBEDDING}" <=> :embedding
            LIMIT :top_k
            """)
        result = db.execute(query, {
            "embedding": embedding_str,
            "top_k": top_k
        })
        documents = [row[0] for row in result.fetchall()]
        logger.info(f"Retrieved {len(documents)} similar documents from DB.")
        return documents
    except sqlalchemy.exc.SQLAlchemyError as e:
        logger.error(f"Database error during similarity search: {e}",
                     exc_info=True)
        return []
    except Exception as e:
        logger.error(f"Unexpected error during similarity search: {e}",
                     exc_info=True)
        return []


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
