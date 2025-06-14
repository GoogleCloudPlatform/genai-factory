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

# Google Cloud Storage Configuration (for the SOURCE file)
GCS_SOURCE_BUCKET = os.environ.get("GCS_SOURCE_BUCKET")
GCS_SOURCE_BLOB_NAME = os.environ.get("GCS_SOURCE_BLOB_NAME", "data.jsonl")

# Embedding Model Configuration
EMBEDDING_MODEL_NAME = os.environ.get("EMBEDDING_MODEL_NAME",
                                      "text-multilingual-embedding-002")
EMBEDDING_DIMENSIONS = int(os.environ.get("EMBEDDING_DIMENSIONS", 768))
EMBEDDING_BATCH_SIZE = int(os.environ.get(
    "EMBEDDING_BATCH_SIZE", 200))  # Batch for calling the embedding model API

# Vector Search Configuration
VECTOR_SEARCH_INDEX_NAME = os.environ.get("VECTOR_SEARCH_INDEX_NAME")
# Batch size for the upsert_datapoints API call (max 1000, recommended 100-200)
VECTOR_SEARCH_UPSERT_BATCH_SIZE = int(
    os.environ.get("VECTOR_SEARCH_UPSERT_BATCH_SIZE", 100))
