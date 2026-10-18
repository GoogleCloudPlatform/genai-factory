# Frontend for RAG Search on Cloud Run

The application answers user prompts by performing Hybrid Search (Semantic Search with auto-embeddings + Text Search combined via Reciprocal Rank Fusion) on a Vertex AI Vector Search 2.0 Collection and generating grounded responses with Gemini.

## Use the application

```shell
curl -X POST https://YOUR_DOMAIN/predict \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d '{"prompt":"Can you recommend a great action movie?"}'
```

Expected output:

```json
{
    "prompt": "Can you recommend a great action movie?",
    "augmented_prompt": "Based on the following context, answer the question.\n\nContext:\n...",
    "prediction": "..."
}
```

## Environment variables

Refer to [./src/config.py](./src/config.py) for the list of environment variables and defaults.
