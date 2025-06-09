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
REGION = os.environ.get("REGION")

# GCS Configuration
GCS_BUCKET_NAME = os.environ.get("GCS_BUCKET_NAME")
GCS_CSV_FILENAME = os.environ.get("GCS_CSV_FILENAME", "data.csv")

# Vertex Configuration
INDEX_ID = os.environ.get("VERTEX_INDEX_ID", "gf-rrag-0")
EMBEDDING_MODEL_NAME = os.environ.get("EMBEDDING_MODEL_NAME", "text-multilingual-embedding-002")
EMBEDDING_BATCH_SIZE = os.environ.get("EMBEDDING_BATCH_SIZE", 5)
UPSERT_BATCH_SIZE = os.environ.get("EMBEDDING_BATCH_SIZE", 100)
