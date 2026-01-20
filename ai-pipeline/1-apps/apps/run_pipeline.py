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
from google.cloud import aiplatform_v1
import google.cloud.compute_v1 as compute_v1
import google.cloud.dns as dns

def run_pipeline(project: str, region: str, pipeline_root: str, csv_gcs_path: str,
                 service_account: str = None, network_attachment: str = None, 
                 db_host: str = None, target_network: str = None, dns_domain: str = "sql.goog.",
                 proxy_url: str = None):
    """Initializes and runs a Vertex AI pipeline job using the GAPIC client."""
    
    # 1. Initialize AI Platform (SDK still useful for some utils, but we use GAPIC for job creation)
    aiplatform.init(project=project, location=region)

    parameter_values = {
        "csv_gcs_path": csv_gcs_path
    }
    if db_host:
        parameter_values["db_host"] = db_host
    if proxy_url:
        parameter_values["proxy_url"] = proxy_url

    # 2. Prepare Pipeline Spec (Read YAML manually)
    import yaml
    with open("pipeline.yaml", "r") as f:
        pipeline_spec = yaml.safe_load(f)

    # 3. Request Construction
    api_client = aiplatform.gapic.PipelineServiceClient(
        client_options={"api_endpoint": f"{region}-aiplatform.googleapis.com"}
    )

    # Runtime config
    runtime_config = aiplatform_v1.PipelineJob.RuntimeConfig(
        gcs_output_directory=pipeline_root,
        parameter_values=parameter_values
    )

    # PSC Interface Config
    psc_config = None
    if network_attachment:
        psc_interface_config_dict = {
            "network_attachment": network_attachment,
        }
        if target_network and dns_domain:
            psc_interface_config_dict["dns_peering_configs"] = [
                {
                    "domain": dns_domain,
                    "target_project": project,
                    "target_network": target_network
                }
            ]

        # Create PscInterfaceConfig from the dictionary
        psc_config = aiplatform_v1.PscInterfaceConfig(psc_interface_config_dict)

    pipeline_job = aiplatform_v1.PipelineJob(
        display_name="private-data-run",
        pipeline_spec=pipeline_spec,
        runtime_config=runtime_config,
        service_account=service_account,
        psc_interface_config=psc_config,
    )

    parent = f"projects/{project}/locations/{region}"
    request = aiplatform_v1.CreatePipelineJobRequest(
        parent=parent,
        pipeline_job=pipeline_job,
    )

    print("Submitting Pipeline Job via GAPIC...")
    response = api_client.create_pipeline_job(request=request)
    print(f"Pipeline job created: {response.name}")
    print(f"View job in console: https://console.cloud.google.com/vertex-ai/locations/{region}/pipelines/runs/{response.name.split('/')[-1]}?project={project}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run a Vertex AI pipeline.")
    parser.add_argument("--project", required=True, help="Google Cloud project ID")
    parser.add_argument("--region", default="us-central1", help="Google Cloud region")
    parser.add_argument("--pipeline_root", required=True, help="GCS bucket root for pipeline outputs (e.g., gs://my-bucket/output)")
    parser.add_argument("--csv_gcs_path", required=True, help="GCS path for the input CSV data (e.g., gs://my-bucket/data.csv)")
    parser.add_argument("--service_account", help="Service account email to run the pipeline steps")
    parser.add_argument("--network_attachment", help="PSC Network Attachment ID for private connectivity")
    parser.add_argument("--db_host", help="Private DNS name of the Cloud SQL instance")
    parser.add_argument("--target_network", help="Full resource URL of the target VPC network")
    parser.add_argument("--dns_domain", default="sql.goog.", help="DNS domain to peer (default: sql.goog.)")
    parser.add_argument("--proxy_url", help="Secure Web Proxy URL (e.g. https://10.129.0.2:443)")

    args = parser.parse_args()
    
    run_pipeline(
        project=args.project,
        region=args.region,
        pipeline_root=args.pipeline_root,
        csv_gcs_path=args.csv_gcs_path,
        service_account=args.service_account,
        network_attachment=args.network_attachment,
        db_host=args.db_host,
        target_network=args.target_network,
        dns_domain=args.dns_domain,
        proxy_url=args.proxy_url
    )
