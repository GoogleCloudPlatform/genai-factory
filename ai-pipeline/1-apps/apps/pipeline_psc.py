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

import argparse

from google.cloud import aiplatform


def create_custom_job_psci_sample(
    project: str,
    location: str,
    bucket: str,
    display_name: str,
    machine_type: str,
    replica_count: int,
    image_uri: str,
    network_attachment: str,
    target_project: str,
    target_network: str,
    input_file: str,
    service_account: str,
    db_host: str,
    db_name: str,
    db_user: str,
    proxy_url: str = None,
    proxy_port: str = "443",
    dns_peering_domains: list = ["sql.goog."],
):
    """Custom training job sample with PSC Interface Config."""
    aiplatform.init(project=project, location=location, staging_bucket=bucket)

    # Python script to read from GCS and write to Cloud SQL
    python_script = f"""
import time
import os
import subprocess
import sys
import traceback

# Configure Proxy if provided
if "{proxy_url}":
    os.environ["http_proxy"] = f"http://{proxy_url}:{proxy_port}"
    os.environ["https_proxy"] = f"http://{proxy_url}:{proxy_port}"    
    os.environ["no_proxy"] = "localhost,127.0.0.1,metadata.google.internal,169.254.169.254,.googleapis.com,.google.internal"
    print(f"DEBUG: Proxy configured: {{os.environ['http_proxy']}}")

# Install dependencies at runtime
print("Installing dependencies...")
subprocess.check_call([
    sys.executable, "-m", "pip", "install", "--upgrade",
    "sqlalchemy", "pg8000", "google-cloud-storage"
])

import certifi
import logging
import requests
import ssl
from google.cloud import storage
import sqlalchemy
import pandas as pd
import google.auth
from google.auth.transport.requests import Request

# Configure standard logging to stdout
# Vertex AI captures stdout/stderr automatically, so this will appear in Cloud Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s: %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger()

logger.info('Starting PSC Job')

input_file = "{input_file}"
db_host = "{db_host}"
db_name = "{db_name}"
db_user = "{db_user}"

# Cloud SQL Postgres IAM requires stripping .gserviceaccount.com from the username
if db_user.endswith(".gserviceaccount.com"):
    db_user = db_user.replace(".gserviceaccount.com", "")
    logger.info(f"Adjusted DB User for IAM Auth: {{db_user}}")

logger.info(f'Reading file: {{input_file}}')

try:
    # Read GCS File
    if input_file.startswith("gs://"):
        logger.info(f"Reading CSV from GCS: {{input_file}}")
        # Parse bucket and blob
        parts = input_file[5:].split("/", 1)
        bucket_name = parts[0]
        blob_name = parts[1]
        
        storage_client = storage.Client()
        bucket_obj = storage_client.bucket(bucket_name)
        blob = bucket_obj.blob(blob_name)
        
        local_path = "/tmp/input.csv"
        logger.info(f"Downloading {{input_file}} to {{local_path}}...")
        blob.download_to_filename(local_path)
        logger.info("Download complete.")
        
        df = pd.read_csv(local_path)
        logger.info("Data loaded into DataFrame:")
        logger.info(df.head())
    else:
        logger.info(f"Input file {{input_file}} is not a GCS path. Exiting.")
        sys.exit(1)

    # Connect to Cloud SQL (PostgreSQL)
    logger.info(f"Connecting to Database {{db_name}} at {{db_host}} as {{db_user}}...")
    
    scopes = ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/sqlservice.login"]
    credentials, project = google.auth.default(scopes=scopes)
    auth_req = Request()
    credentials.refresh(auth_req)
    access_token = credentials.token
    
    db_url = f"postgresql+pg8000://{{db_user}}:{{access_token}}@{{db_host}}:5432/{{db_name}}"
    
    engine = sqlalchemy.create_engine(db_url)

    # Write to SQL
    logger.info("Writing to SQL...")
    # Assuming table name 'imdb' for this demo, or derive from filename
    table_name = "imdb" 
    
    # Use 'replace' to ensure fresh table (requires DROP permissions)
    try:
        df.to_sql(table_name, engine, if_exists='replace', index=False)
        logger.info(f"Successfully wrote {{len(df)}} rows to table '{{table_name}}'.")
    except Exception as e:
        logger.info(f"Replace failed: {{e}}. Trying append...")
        # Fallback to append if replace fails (e.g. permission issues)
        df.to_sql(table_name, engine, if_exists='append', index=False)
    
    # Verify and Grant Permissions
    with engine.connect() as conn:
        # Grant usage on schema and select on table
        logger.info(f"Granting permissions to PUBLIC...")
        conn.execute(sqlalchemy.text("GRANT USAGE ON SCHEMA public TO PUBLIC"))
        conn.execute(sqlalchemy.text(f"GRANT SELECT ON {{table_name}} TO PUBLIC"))
        conn.commit()
        
        result = conn.execute(sqlalchemy.text(f"SELECT count(*) FROM {{table_name}}"))
        logger.info(f"Count in DB: {{result.scalar()}}")

except Exception as e:
    logger.error(f"Error: {{e}}", exc_info=True)

logger.info('Job complete. Sleeping for 10 seconds...')
time.sleep(10)
"""

    worker_pool_specs = [{
        "machine_spec": {
            "machine_type": machine_type,
        },
        "replica_count": replica_count,
        "container_spec": {
            "image_uri": image_uri,
            "command": ["python3", "-c"],
            "args": [python_script],
        },
    }]

    dns_configs = []
    for d in dns_peering_domains:
        dns_configs.append({
            "domain": d,
            "target_project": target_project,
            "target_network": target_network,
        })

    psc_interface_config = {
        "network_attachment": network_attachment,
        "dns_peering_configs": dns_configs,
    }
    job = aiplatform.CustomJob(
        display_name=display_name,
        worker_pool_specs=worker_pool_specs,
    )

    job.run(
        psc_interface_config=psc_interface_config,
        service_account=service_account,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--service_account", required=True)
    parser.add_argument("--input_file",
                        required=True,
                        help="GCS URI of the file to read")
    # Database args
    parser.add_argument("--db_host",
                        required=True,
                        help="Database Host (IP or DNS)")
    parser.add_argument("--db_name",
                        default="cloud-sql-db",
                        help="Database Name")
    parser.add_argument("--db_user",
                        required=True,
                        help="Database User (SA Email)")
    # Network args
    parser.add_argument("--network_attachment",
                        help="PSC Network Attachment ID")
    parser.add_argument("--target_network", help="Target VPC Network URL")
    parser.add_argument("--dns_domains",
                        default=["sql.goog."],
                        nargs="+",
                        help="DNS Domains to peer (list)")
    parser.add_argument("--proxy_url", help="Secure Web Proxy URL")
    parser.add_argument("--proxy_port",
                        default="443",
                        help="Secure Web Proxy Port")

    args = parser.parse_args()

    create_custom_job_psci_sample(
        project=args.project,
        location=args.region,
        bucket=args.bucket,
        display_name="pipeline-psc",
        machine_type="n2-standard-4",
        replica_count=1,
        image_uri=
        "us-docker.pkg.dev/vertex-ai/training/tf-cpu.2-17.py310:latest",
        network_attachment=args.network_attachment,
        target_project=args.project,
        target_network=args.target_network,
        input_file=args.input_file,
        service_account=args.service_account,
        db_host=args.db_host,
        db_name=args.db_name,
        db_user=args.db_user,
        proxy_url=args.proxy_url,
        proxy_port=args.proxy_port,
        dns_peering_domains=args.dns_domains,
    )
