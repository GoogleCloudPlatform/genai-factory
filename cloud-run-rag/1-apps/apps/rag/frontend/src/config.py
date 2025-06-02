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
MODEL_NAME = os.environ.get("MODEL_NAME", "gemini-2.0-flash")
TEMPERATURE = float(os.environ.get("TEMPERATURE", 0.7))
TOP_P = float(os.environ.get("TOP_P", 1.0))
TOP_K = int(os.environ.get("TOP_K", 32))
CANDIDATE_COUNT = int(os.environ.get("CANDIDATE_COUNT", 1))
MAX_OUTPUT_TOKENS = int(os.environ.get("MAX_OUTPUT_TOKENS", 2048))

# Embedding Model Configuration
EMBEDDING_MODEL_NAME = os.environ.get("EMBEDDING_MODEL_NAME", "text-multilingual-embedding-002")
EMBEDDING_TASK_TYPE = "RETRIEVAL_QUERY"

# DB configuration
DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
DB_PORT = int(os.environ.get("DB_PORT", 5432))
DB_NAME = os.environ.get("DB_NAME")
DB_SA = os.environ.get("DB_SA")
DB_TABLE = os.environ.get("DB_TABLE", "movie_embeddings")
DB_COLUMN_TEXT = os.environ.get("DB_COLUMN_TEXT", "content_to_embed")
DB_COLUMN_EMBEDDING = os.environ.get("DB_COLUMN_EMBEDDING", "embedding")
