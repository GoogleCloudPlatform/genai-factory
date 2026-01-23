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
    domain: str,
    target_project: str,
    target_network: str,
    input_file: str,
    service_account: str,
    db_host: str,
    db_name: str,
    db_user: str,
    proxy_url: str = None,
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
    print(f"Proxy configured: {{os.environ['https_proxy']}}")

print("Installing dependencies...")
subprocess.check_call([sys.executable, "-m", "pip", "install", "sqlalchemy", "pg8000", "pandas", "google-auth"])

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
        df = pd.read_csv(input_file)
        print("Data loaded into DataFrame:")
        print(df.head())
    else:
        print(f"Input file {{input_file}} is not a GCS path. Exiting.")
        sys.exit(1)

    # 2. Connect to Cloud SQL (PostgreSQL)
    print(f"Connecting to Database {{db_name}} at {{db_host}} as {{db_user}}...")
    
    # Get IAM Access Token for Password
    scopes = ["https://www.googleapis.com/auth/sqlservice.login"]
    credentials, project = google.auth.default(scopes=scopes)
    auth_req = Request()
    credentials.refresh(auth_req)
    access_token = credentials.token
    
    # Create Engine
    # user:password@host:port/dbname
    # We use pg8000 driver
    db_url = f"postgresql+pg8000://{{db_user}}:{{access_token}}@{{db_host}}:5432/{{db_name}}"
    
    engine = sqlalchemy.create_engine(db_url)
    
    # 3. Write to SQL
    print("Writing to SQL...")
    table_name = "imdb" 
    df.to_sql(table_name, engine, if_exists='replace', index=False)
    print(f"Successfully wrote {{len(df)}} rows to table '{{table_name}}'.")
    
    # Verify
    with engine.connect() as conn:
        result = conn.execute(sqlalchemy.text(f"SELECT count(*) FROM {{table_name}}"))
        print(f"Count in DB: {{result.scalar()}}")

except Exception as e:
    print(f"Error: {{e}}")

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
    psc_interface_config = {
        "network_attachment": network_attachment,
        "dns_peering_configs": [
            {
                "domain": domain,
                "target_project": target_project,
                "target_network": target_network,
            },
        ],
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
    parser.add_argument("--input_file", required=True, help="GCS URI of the file to read")
    # Database args
    parser.add_argument("--db_host", required=True, help="Database Host (IP or DNS)")
    parser.add_argument("--db_name", default="cloud-sql-db", help="Database Name")
    parser.add_argument("--db_user", required=True, help="Database User (SA Email)")
    # Network args
    parser.add_argument("--network_attachment", help="PSC Network Attachment ID")
    parser.add_argument("--target_network", help="Target VPC Network URL")
    parser.add_argument("--dns_domain", default="sql.goog.", help="DNS Domain to peer")
    parser.add_argument("--proxy_url", help="Secure Web Proxy URL")
    
    args = parser.parse_args()

    create_custom_job_psci_sample(
        project=args.project,
        location=args.region,
        bucket=args.bucket,
        display_name="pipeline-psc",
        machine_type="n2-standard-4",
        replica_count=1,
        image_uri="us-docker.pkg.dev/vertex-ai/training/tf-cpu.2-14.py310:latest",
        network_attachment=args.network_attachment,
        domain=args.dns_domain,
        target_project=args.project,
        target_network=args.target_network,
        input_file=args.input_file,
        service_account=args.service_account,
        db_host=args.db_host,
        db_name=args.db_name,
        db_user=args.db_user,
        proxy_url=args.proxy_url,
    )