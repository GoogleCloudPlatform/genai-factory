# Chat application for Cloud Run (Private Model Garden Endpoint)

A simple chat application calling a privately exposed Vertex AI Model Garden endpoint over Private Service Connect (PSC) and exposing a JSON interface.

## Use the application

```shell
curl -X POST https://YOUR_DOMAIN/predict \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d '{"prompt":"hello world!"}'
```

## Environment variables

- `PROJECT_ID`: the project ID where the Vertex AI Private Endpoint is deployed.
- `REGION`: the GCP region (defaults to `europe-west1`).
- `ENDPOINT_ID`: the Vertex AI Private Endpoint ID.
- `ENDPOINT_IP_ADDRESS`: the Private Service Connect consumer IP address targeting the endpoint's service attachment.
- `MODEL_ARMOR_TEMPLATE`: the optional Model Armor template resource name for prompt and response sanitization.
