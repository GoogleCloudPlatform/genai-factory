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

# BigQuery Configuration
BQ_DATASET = os.environ.get("BQ_DATASET", "gf-rrag-0")
BQ_TABLE = os.environ.get("BQ_TABLE", "gf-rrag-0")
BQ_BATCH_SIZE = int(os.environ.get("BATCH_SIZE_BQ", 1000))

# Generative Model Configuration
MODEL_NAME = os.environ.get("MODEL_NAME", "gemini-2.0-flash")
TEMPERATURE = float(os.environ.get("TEMPERATURE", 0.7))
TOP_P = float(os.environ.get("TOP_P", 1.0))
TOP_K = int(os.environ.get("TOP_K", 32))
CANDIDATE_COUNT = int(os.environ.get("CANDIDATE_COUNT", 1))
MAX_OUTPUT_TOKENS = int(os.environ.get("MAX_OUTPUT_TOKENS", 2048))

# Embedding Model Configuration
EMBEDDING_MODEL_NAME = os.environ.get("EMBEDDING_MODEL_NAME", "text-multilingual-embedding-002")
EMBEDDING_DIMENSIONS = int(os.environ.get("EMBEDDING_DIMENSIONS", 768))
EMBEDDING_BATCH_SIZE = int(os.environ.get("BATCH_SIZE_EMBEDDING", 200))

# DB configuration
DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
DB_PORT = int(os.environ.get("DB_PORT", 5432))
DB_NAME = os.environ.get("DB_NAME")
DB_SA = os.environ.get("DB_SA")
DB_TABLE = os.environ.get("DB_TABLE", "movie_embeddings")

# Columns Configuration
GENERATED_ID_COLUMN_NAME = os.environ.get("GENERATED_ID_COLUMN_NAME", "id")
BQ_TEXT_COLUMNS_STR = os.environ.get("BQ_TEXT_COLUMNS", "title,description")
TARGET_BQ_COLUMNS_DEFAULT = ['rank', 'title', 'description', 'genre', 'rating', 'year']
