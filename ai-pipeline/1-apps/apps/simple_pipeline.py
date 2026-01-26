import os
import argparse
from kfp import dsl
from kfp import compiler
from google.cloud import aiplatform

# Define the Hello World component
# We remove packages_to_install because we don't import kfp inside the component
# This avoids pip install and proxy issues entirely for Hello World
@dsl.component(base_image="python:3.10")
def hello_world_component() -> str:
    import logging
    import sys
    import os
    import getpass
    import time
    
    logging.basicConfig(stream=sys.stdout, level=logging.INFO)
    logger = logging.getLogger("hello_world")

    logger.info("HELLO WORLD - Success!")
    logger.info(f"Running as user: {getpass.getuser()}")
    logger.info(f"Execution time: {time.time()}")
    
    return "Hello World Success"

@dsl.pipeline(
    name="simple-hello-world",
    description="A minimal Hello World pipeline."
)
def simple_pipeline(proxy_url: str = "http://replace-me"):
    hello_task = hello_world_component()
    # No proxy needed for pure Hello World with no pip install

from google.cloud import aiplatform_v1

def run_job(project: str, region: str, pipeline_root: str, service_account: str, 
            network_attachment: str = None, target_network: str = None, dns_domain: str = "sql.goog.",
            proxy_url: str = None):
    # Compile the pipeline
    compiler.Compiler().compile(
        pipeline_func=simple_pipeline,
        package_path="simple_pipeline.yaml"
    )
    print("Pipeline compiled to simple_pipeline.yaml")

    # Initialize Vertex AI SDK (still needed for some setup)
    aiplatform.init(project=project, location=region)

    parameter_values = {}
    if proxy_url:
        parameter_values["proxy_url"] = proxy_url

    # Prepare the Pipeline Job arguments
    # We use the GAPIC client directly to support psc_interface_config
    api_client = aiplatform.gapic.PipelineServiceClient(
        client_options={"api_endpoint": f"{region}-aiplatform.googleapis.com"}
    )

    # 1. Pipeline Spec
    import yaml
    with open("simple_pipeline.yaml", "r") as f:
        pipeline_spec = yaml.safe_load(f)

    # 2. Runtime Config
    runtime_config = aiplatform_v1.PipelineJob.RuntimeConfig(
        gcs_output_directory=pipeline_root,
        parameter_values=parameter_values
    )

    # 3. PSC Interface Config
    psc_config = None
    if network_attachment:
        print(f"Configuring PSC Interface with attachment: {network_attachment}")
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
        psc_config = aiplatform_v1.PscInterfaceConfig(psc_interface_config_dict)

    # 4. Create Job Spec
    pipeline_job = aiplatform_v1.PipelineJob(
        display_name="simple-hello-world-psc",
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--pipeline_root", required=True)
    parser.add_argument("--service_account", required=True)
    # Network args
    parser.add_argument("--network_attachment", help="PSC Network Attachment ID")
    parser.add_argument("--target_network", help="Target VPC Network URL")
    parser.add_argument("--dns_domain", default="sql.goog.", help="DNS Domain to peer")
    parser.add_argument("--proxy_url", help="Secure Web Proxy URL")
    
    args = parser.parse_args()
    
    run_job(
        project=args.project,
        region=args.region,
        pipeline_root=args.pipeline_root,
        service_account=args.service_account,
        network_attachment=args.network_attachment,
        target_network=args.target_network,
        dns_domain=args.dns_domain,
        proxy_url=args.proxy_url
    )
