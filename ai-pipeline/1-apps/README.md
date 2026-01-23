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

3. Run the pipeline:
    ```shell
    # Extract the project ID and service account from the 0-projects stage
    export PROJECT_ID=$(cd ../0-projects && terraform output -json projects | jq -r '.project.id')
    export SA_EMAIL=$(cd ../0-projects && terraform output -json service_accounts | jq -r '."project/gf-pipeline-0".email')

    # Extract info from current stage
    export REGION=$(terraform output -raw region)
    export NETWORK_ATTACHMENT=$(terraform output -raw network_attachment)
    export TARGET_NETWORK=$(terraform output -raw target_network)
    export DB_HOST=$(terraform output -raw db_host)

    # Run the script
    python3 apps/run_pipeline.py \
      --project $PROJECT_ID \
      --region $REGION \
      --service_account $SA_EMAIL \
      --network_attachment $ATTACHMENT_ID \
      --target_network $TARGET_NETWORK \
      --db_host $DB_HOST \
      --dns_domain "sql.goog." \
      --csv_gcs_path gs://$PROJECT_ID-pipeline-artifacts/data/top-100-imdb-movies.csv \
      --pipeline_root gs://$PROJECT_ID-pipeline-artifacts/output
    ```

python3 apps/pipeline_psc.py  --project $PROJECT_ID   --region $REGION   --bucket gs://$PROJECT_ID-pipeline-artifacts/output   --service_account $SA_EMAIL   --network_attachment $NETWORK_ATTACHMENT   --target_network $TARGET_NETWORK   --dns_domain "sql.goog." 