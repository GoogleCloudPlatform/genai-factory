# Ingestion for RAG Search on Cloud Run

The application reads [data.jsonl](../../../data/data.jsonl) from Cloud Storage and upserts `DataObject` records into a Vertex AI Vector Search 2.0 Collection, which automatically generates embeddings via its configured `vertex_embedding_config`.

## Environment variables

Refer to [./src/config.py](./src/config.py) for the list of environment variables and defaults.
