# Gemma3 on Cloud Run GPU

An example for running a self-hosted [Gemma 3](https://ai.google.dev/gemma/docs/core) model on a Cloud Run Service with Nvidia L4 GPUs.

## Use the application

```shell
curl -X POST https://YOUR_DOMAIN/api/generate \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d '{
  "model": "gemma3:4b",
  "prompt": "Why is the sky blue?"
}'
```
