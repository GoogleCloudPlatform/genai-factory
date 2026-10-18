# Copyright 2026 Google LLC
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

# Vector Search 2.0 Configuration
VECTOR_SEARCH_COLLECTION_ID = os.environ.get("VECTOR_SEARCH_COLLECTION_ID")
VECTOR_SEARCH_LOCATION = os.environ.get("VECTOR_SEARCH_LOCATION", REGION)
# Batch size for batch_create_data_objects / batch_update_data_objects
# (max 250 when using Vertex AI auto-embeddings)
VECTOR_SEARCH_UPSERT_BATCH_SIZE = int(
    os.environ.get("VECTOR_SEARCH_UPSERT_BATCH_SIZE", 100))
