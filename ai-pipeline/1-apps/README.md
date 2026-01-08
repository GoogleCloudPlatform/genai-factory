# Vertex AI Pipeline / Platform Deployment

This stage provisions the infrastructure for Vertex AI pipelines, including a GCS bucket for artifacts and an Artifact Registry for images.

## Deploy the stage

```shell
terraform init
terraform apply
```

## Run the pipeline

1.  Create a virtual environment:
    ```shell
    python3 -m venv venv
    source venv/bin/activate
    pip install kfp google-cloud-aiplatform
    ```

2.  Compile the pipeline:
    ```shell
    python3 apps/pipeline.py
    ```

3.  Run the pipeline:
    ```shell
    # Extract the project ID and service account from the 0-projects stage
    export PROJECT_ID=$(cd ../0-projects && terraform output -json projects | jq -r '.project.id')
    export SA_EMAIL=$(cd ../0-projects && terraform output -json service_accounts | jq -r '."project/gf-pipeline-0".email')

    # (Optional) Extract the network attachment ID for PSC Interface
    export ATTACHMENT_ID=$(terraform output -json network_attachment | jq -r '.')

    # Run the script
    python3 apps/run_pipeline.py \
      --project $PROJECT_ID \
      --service_account $SA_EMAIL \
      --network_attachment $ATTACHMENT_ID \
      --pipeline_root gs://$PROJECT_ID-pipeline-artifacts/output
    ```
