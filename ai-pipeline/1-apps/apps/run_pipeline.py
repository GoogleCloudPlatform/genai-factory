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

def run_pipeline(project: str, region: str, pipeline_root: str, service_account: str = None, network_attachment: str = None):
    """Initializes and runs a Vertex AI pipeline job."""
    
    aiplatform.init(project=project, location=region)

    job = aiplatform.PipelineJob(
        display_name="hello-world-run",
        template_path="pipeline.yaml",
        pipeline_root=pipeline_root,
    )

    psc_interface_config = None
    if network_attachment:
        psc_interface_config = aiplatform.PrivateServiceConnectInterfaceConfig(
            network_attachment=network_attachment
        )

    job.run(
        service_account=service_account,
        psc_interface_config=psc_interface_config
    )
    print("Pipeline job started successfully.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run a Vertex AI pipeline.")
    parser.add_argument("--project", required=True, help="Google Cloud project ID")
    parser.add_argument("--region", default="us-central1", help="Google Cloud region")
    parser.add_argument("--pipeline_root", required=True, help="GCS bucket root for pipeline outputs (e.g., gs://my-bucket/output)")
    parser.add_argument("--service_account", help="Service account email to run the pipeline steps")
    parser.add_argument("--network_attachment", help="PSC Network Attachment ID for private connectivity")

    args = parser.parse_args()
    
    run_pipeline(
        project=args.project,
        region=args.region,
        pipeline_root=args.pipeline_root,
        service_account=args.service_account,
        network_attachment=args.network_attachment
    )
