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

from kfp import dsl
from kfp import compiler

@dsl.component(packages_to_install=["pg8000", "pandas", "sqlalchemy", "google-cloud-storage"], base_image="us-docker.pkg.dev/vertex-ai/training/scikit-learn-cpu.0-23:latest")
def load_csv_to_sql_component(
    db_host: str, 
    db_name: str, 
    db_user: str, 
    csv_gcs_path: str,
    proxy_url: str = None
) -> str:
    import logging
    import sys
    import os
    import pandas as pd
    from sqlalchemy import create_engine, text
    from google.cloud import storage
    import io
    import socket

    # Configure logging to stdout so Cloud Logging picks it up
    logging.basicConfig(stream=sys.stdout, level=logging.INFO)
    logger = logging.getLogger("load_csv_to_sql")

    if proxy_url:
        logger.info(f"Setting proxy to {proxy_url}")
        os.environ["http_proxy"] = proxy_url
        os.environ["https_proxy"] = proxy_url

    logger.info("Starting load_csv_to_sql_component")
    
    # 1. Diagnostic: Check network environment
    try:
        hostname = socket.gethostname()
        ip_address = socket.gethostbyname(hostname)
        logger.info(f"Running on hostname: {hostname}, IP: {ip_address}")
        logger.info(f"Target DB Host: {db_host}")
        
        # Resolve DB host
        db_ip = socket.gethostbyname(db_host)
        logger.info(f"Resolved DB Host {db_host} to IP: {db_ip}")
    except Exception as e:
        logger.warning(f"Network diagnostic failed: {e}")

    # 2. Download CSV from GCS
    try:
        logger.info(f"Downloading CSV from: {csv_gcs_path}")
        if not csv_gcs_path.startswith("gs://"):
            raise ValueError(f"Invalid GCS path: {csv_gcs_path}")
        
        path_segments = csv_gcs_path.replace("gs://", "").split("/", 1)
        bucket_name = path_segments[0]
        blob_name = path_segments[1]
        
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        content = blob.download_as_text()
        
        df = pd.read_csv(io.StringIO(content))
        logger.info(f"Successfully loaded {len(df)} rows from {csv_gcs_path}")
        logger.info(f"Columns: {df.columns.tolist()}")
    except Exception as e:
        logger.exception("Failed to load CSV from GCS")
        raise e

    # 3. Connect to Cloud SQL and load data
    try:
        logger.info(f"Connecting to Postgres at {db_host}...")
        # Connection string for pg8000
        engine = create_engine(f"postgresql+pg8000://{db_user}@{db_host}/{db_name}")
        
        # Test connection
        with engine.connect() as connection:
            result = connection.execute(text("SELECT 1"))
            logger.info("Database connection test successful.")

        # Create table if not exists and load data
        logger.info("Writing dataframe to SQL...")
        df.to_sql("imdb_movies", engine, if_exists="replace", index=False)
        
        logger.info(f"Successfully loaded data into table 'imdb_movies' in {db_name}")
        return "Success"
    except Exception as e:
        logger.exception("Failed to load data into Cloud SQL")
        raise e

@dsl.pipeline(
    name="private-data-pipeline",
    description="A pipeline that loads CSV data into a private Cloud SQL instance."
)
def private_data_pipeline(
    db_host: str, 
    csv_gcs_path: str,
    proxy_url: str = None,
    db_name: str = "cloud-sql-db", 
    db_user: str = "postgres"
):
    load_task = load_csv_to_sql_component(
        db_host=db_host,
        db_name=db_name,
        db_user=db_user,
        csv_gcs_path=csv_gcs_path,
        proxy_url=proxy_url
    )

if __name__ == "__main__":
    compiler.Compiler().compile(
        pipeline_func=private_data_pipeline,
        package_path="pipeline.yaml"
    )
    print("Pipeline compiled successfully to pipeline.yaml")
