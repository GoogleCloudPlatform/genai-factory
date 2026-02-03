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

import time
import sys
import logging

import sqlalchemy
import pandas as pd
import google.auth
from google.auth.transport.requests import Request
from google.cloud import storage

from src import config

logging.basicConfig(level=logging.INFO,
                    format='%(levelname)s: %(message)s',
                    stream=sys.stdout)
logger = logging.getLogger()

logger.info('Starting PSC Job')

if config.PROXY_ADDRESS:
    logger.info(f"Using Proxy: {config.PROXY_ADDRESS}:{config.PROXY_PORT}")

# Cloud SQL Postgres IAM requires stripping .gserviceaccount.com from the username
if config.DB_USER and config.DB_USER.endswith(".gserviceaccount.com"):
    db_user = config.DB_USER.replace(".gserviceaccount.com", "")
    logger.info(f"Adjusted DB User for IAM Auth: {config.DB_USER}")

logger.info(f'Reading file: {config.INPUT_FILE}')

try:
    # Read GCS File
    if config.INPUT_FILE and config.INPUT_FILE.startswith("gs://"):
        logger.info(f"Reading CSV from GCS: {config.INPUT_FILE}")
        # Parse bucket and blob
        parts = config.INPUT_FILE[5:].split("/", 1)
        bucket_name = parts[0]
        blob_name = parts[1]

        storage_client = storage.Client()
        bucket_obj = storage_client.bucket(bucket_name)
        blob = bucket_obj.blob(blob_name)

        local_path = "/tmp/input.csv"
        logger.info(f"Downloading {config.INPUT_FILE} to {local_path}...")
        blob.download_to_filename(local_path)
        logger.info("Download complete.")

        df = pd.read_csv(local_path)
        logger.info("Data loaded into DataFrame:")
        logger.info(df.head())
    else:
        logger.info(f"Input file {config.INPUT_FILE} is not a GCS path or "
                    "missing. Exiting.")
        sys.exit(1)

    logger.info(f"Connecting to Database {config.DB_NAME} at {config.DB_HOST} as {config.DB_USER}...")

    scopes = ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/sqlservice.login"]
    credentials, project = google.auth.default(scopes=scopes)
    auth_req = Request()
    credentials.refresh(auth_req)
    access_token = credentials.token

    db_url = f"postgresql+pg8000://{db_user}:{access_token}@{config.DB_HOST}:5432/{config.DB_NAME}"

    engine = sqlalchemy.create_engine(db_url)

    logger.info("Writing to SQL...")
    table_name = "imdb"

    # Use 'replace' to ensure fresh table (requires DROP permissions)
    try:
        df.to_sql(table_name, engine, if_exists='replace', index=False)
        logger.info(f"Successfully wrote {len(df)} rows to table '{table_name}'.")
    except Exception as e:
        logger.info(f"Replace failed: {e}. Trying append...")
        # Fallback to append if replace fails (e.g. permission issues)
        df.to_sql(table_name, engine, if_exists='append', index=False)

    # Verify and Grant Permissions
    with engine.connect() as conn:
        # Grant usage on schema and select on table
        logger.info(f"Granting permissions to PUBLIC...")
        conn.execute(sqlalchemy.text("GRANT USAGE ON SCHEMA public TO PUBLIC"))
        conn.execute(sqlalchemy.text(f"GRANT SELECT ON {table_name} TO PUBLIC"))
        conn.commit()

        result = conn.execute(sqlalchemy.text(f"SELECT count(*) FROM {table_name}"))
        logger.info(f"Count in DB: {result.scalar()}")

except Exception as e:
    logger.error(f"Error: {e}", exc_info=True)

logger.info('Job complete. Sleeping for 10 seconds...')
time.sleep(10)
