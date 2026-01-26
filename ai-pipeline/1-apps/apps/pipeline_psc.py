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

print('Starting PSC Job')

# Configure Proxy if provided
if "{proxy_url}" and "{proxy_url}" != "None":
    os.environ["http_proxy"] = "{proxy_url}"
    os.environ["https_proxy"] = "{proxy_url}"
    os.environ["no_proxy"] = "localhost,127.0.0.1,metadata.google.internal,169.254.169.254,.googleapis.com,.google.internal"
    print(f"Proxy configured: {{os.environ['https_proxy']}}")
    print(f"No Proxy configured: {{os.environ.get('no_proxy')}}")

# Install dependencies at runtime
print("Installing dependencies...")
import socket
import ssl
import requests
import certifi
import traceback

# Required to get the TLS certificate from SWP and trust it
try:
    import urllib.parse
    proxy_url_str = "{proxy_url}"
    if proxy_url_str and proxy_url_str != "None":
        parsed = urllib.parse.urlparse(proxy_url_str)
        host = parsed.hostname
        port = parsed.port or (443 if parsed.scheme == 'https' else 80)
        
        print(f"Debug: Fetching proxy certificate from {{host}}:{{port}}...")
        cert_pem = ssl.get_server_certificate((host, port))
        print(f"Debug: Got proxy certificate")

        base_ca_path = certifi.where()
        print(f"Debug: Using base CA bundle from: {{base_ca_path}}")

        with open(base_ca_path, 'r') as f:
            base_ca_content = f.read()
        
        combined_ca_path = "/tmp/combined_ca.pem"
        with open(combined_ca_path, 'w') as f:
            f.write(base_ca_content)
            f.write("\\n")
            f.write(cert_pem)
        
        print(f"Debug: Created combined CA bundle at {{combined_ca_path}}")
        os.environ["REQUESTS_CA_BUNDLE"] = combined_ca_path
        os.environ["SSL_CERT_FILE"] = combined_ca_path # Also help curl/openssl if they respect this
        
        print(f"Debug: Resolving proxy host {{host}}...")
        ip = socket.gethostbyname(host)
        print(f"Debug: Resolved {{host}} to {{ip}}")

    print(f"Debug: Testing connectivity to pypi.org via proxy using curl with CA bundle...")
    subprocess.run(["curl", "-v", "https://pypi.org"], check=False)

except Exception as e:
    print(f"Debug: SSL/Connectivity setup failed: {{e}}")

subprocess.check_call([
    sys.executable, "-m", "pip", "install", 
    "sqlalchemy", "pg8000", "pandas", "google-auth", "google-cloud-storage"
])

from google.cloud import storage
import sqlalchemy
import pandas as pd
import google.auth
from google.auth.transport.requests import Request

input_file = "{input_file}"
db_host = "{db_host}"
db_name = "{db_name}"
db_user = "{db_user}"
# Cloud SQL Postgres IAM requires stripping .gserviceaccount.com from the username
if db_user.endswith(".gserviceaccount.com"):
    db_user = db_user.replace(".gserviceaccount.com", "")
    print(f"Adjusted DB User for IAM Auth: {{db_user}}")

print(f'Reading file: {{input_file}}')

try:
    # 1. Read GCS File
    if input_file.startswith("gs://"):
        print(f"Reading CSV from GCS: {{input_file}}")
        # Parse bucket and blob
        parts = input_file[5:].split("/", 1)
        bucket_name = parts[0]
        blob_name = parts[1]
        
        storage_client = storage.Client()
        bucket_obj = storage_client.bucket(bucket_name)
        blob = bucket_obj.blob(blob_name)
        
        local_path = "/tmp/input.csv"
        print(f"Downloading {{input_file}} to {{local_path}}...")
        blob.download_to_filename(local_path)
        print("Download complete.")
        
        df = pd.read_csv(local_path)
        print("Data loaded into DataFrame:")
        print(df.head())
    else:
        print(f"Input file {{input_file}} is not a GCS path. Exiting.")
        sys.exit(1)

    # 2. Connect to Cloud SQL (PostgreSQL)
    print(f"Connecting to Database {{db_name}} at {{db_host}} as {{db_user}}...")
    
    scopes = ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/sqlservice.login"]
    credentials, project = google.auth.default(scopes=scopes)
    auth_req = Request()
    credentials.refresh(auth_req)
    access_token = credentials.token
    
    db_url = f"postgresql+pg8000://{{db_user}}:{{access_token}}@{{db_host}}:5432/{{db_name}}"
    
    engine = sqlalchemy.create_engine(db_url)

    # 3. Write to SQL
    print("Writing to SQL...")
    # Assuming table name 'imdb' for this demo, or derive from filename
    table_name = "imdb" 
    
    # Use 'replace' to ensure fresh table (requires DROP permissions)
    try:
        df.to_sql(table_name, engine, if_exists='replace', index=False)
        print(f"Successfully wrote {{len(df)}} rows to table '{{table_name}}'.")
    except Exception as e:
        print(f"Replace failed: {{e}}. Trying append...")
        # Fallback to append if replace fails (e.g. permission issues)
        df.to_sql(table_name, engine, if_exists='append', index=False)
    
    # Verify and Grant Permissions
    with engine.connect() as conn:
        # Grant usage on schema and select on table
        print(f"Granting permissions to PUBLIC...")
        conn.execute(sqlalchemy.text("GRANT USAGE ON SCHEMA public TO PUBLIC"))
        conn.execute(sqlalchemy.text(f"GRANT SELECT ON {{table_name}} TO PUBLIC"))
        conn.commit()
        
        result = conn.execute(sqlalchemy.text(f"SELECT count(*) FROM {{table_name}}"))
        print(f"Count in DB: {{result.scalar()}}")

except Exception as e:
    print(f"Error: {{e}}")
    traceback.print_exc()

print('Job complete. Sleeping for 10 seconds...')
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
                        default=["sql.goog.", "proxy.internet."],
                        nargs="+",
                        help="DNS Domains to peer (list)")
    parser.add_argument("--proxy_url", help="Secure Web Proxy URL")

    args = parser.parse_args()

    create_custom_job_psci_sample(
        project=args.project,
        location=args.region,
        bucket=args.bucket,
        display_name="pipeline-psc",
        machine_type="n2-standard-4",
        replica_count=1,
        image_uri=
        "us-docker.pkg.dev/vertex-ai/training/tf-cpu.2-14.py310:latest",
        network_attachment=args.network_attachment,
        target_project=args.project,
        target_network=args.target_network,
        input_file=args.input_file,
        service_account=args.service_account,
        db_host=args.db_host,
        db_name=args.db_name,
        db_user=args.db_user,
        proxy_url=args.proxy_url,
        dns_peering_domains=args.dns_domains,
    )