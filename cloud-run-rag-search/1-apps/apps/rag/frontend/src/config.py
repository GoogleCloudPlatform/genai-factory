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

import os

PROJECT_ID = os.environ.get("PROJECT_ID")
REGION = os.environ.get("REGION", "europe-west1")

# Generative Model Configuration
LLM_MODEL_NAME = os.environ.get("MODEL_NAME", "gemini-2.0-flash")
LLM_TEMPERATURE = float(os.environ.get("TEMPERATURE", 0.2))
LLM_TOP_P = float(os.environ.get("TOP_P", 1.0))
LLM_TOP_K = int(os.environ.get("TOP_K", 40))
LLM_CANDIDATE_COUNT = int(os.environ.get("CANDIDATE_COUNT", 1))
LLM_MAX_OUTPUT_TOKENS = int(os.environ.get("MAX_OUTPUT_TOKENS", 1024))

# Embedding Model Configuration
EMBEDDING_MODEL_NAME = os.environ.get("EMBEDDING_MODEL_NAME",
                                      "text-multilingual-embedding-002")
EMBEDDING_TASK_TYPE = "RETRIEVAL_QUERY"

# Vertex AI Vector Search Configuration
VECTOR_SEARCH_INDEX_ENDPOINT_NAME = os.environ.get(
    "VECTOR_SEARCH_INDEX_ENDPOINT_NAME")
VECTOR_SEARCH_DEPLOYED_INDEX_ID = os.environ.get(
    "VECTOR_SEARCH_DEPLOYED_INDEX_ID")
VECTOR_SEARCH_ENDPOINT_IP_ADDRESS = os.environ.get(
    "VECTOR_SEARCH_ENDPOINT_IP_ADDRESS")

# GCS Source for Document Lookup
GCS_SOURCE_BUCKET = os.environ.get("GCS_SOURCE_BUCKET")
GCS_SOURCE_BLOB_NAME = os.environ.get("GCS_SOURCE_BLOB_NAME", "data.jsonl")
DOCUMENT_CACHE_TTL_SECONDS = int(
    os.environ.get("DOCUMENT_CACHE_TTL_SECONDS", 600))

# Retriever Configuration
RETRIEVER_TOP_K = int(os.environ.get("RETRIEVER_TOP_K", 10))
