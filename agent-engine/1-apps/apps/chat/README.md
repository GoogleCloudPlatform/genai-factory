# Chat application for Cloud Run

A simple chat application leveraging Gemini APIs and exposing a JSON interface.

## Use the application

```shell
curl -X POST https://YOUR_DOMAIN/predict \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d '{"prompt":"hello world!"}'
```

## Environment variables

- `GOOGLE_CLOUD_PROJECT`: the project ID where Vertex AI APIs are called.
- `GOOGLE_CLOUD_LOCATION`: the GCP region (defaults to `europe-west1`).
- `MODEL`: the Vertex AI model name (defaults to `gemini-2.0-flash`).
