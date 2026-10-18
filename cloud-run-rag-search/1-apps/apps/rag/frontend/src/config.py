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
GOOGLE_CLOUD_LOCATION = os.environ.get(
    "GOOGLE_CLOUD_LOCATION",
    "eu" if REGION.startswith("europe") else "us",
)

# Generative Model Configuration
LLM_MODEL_NAME = os.environ.get("MODEL_NAME", "gemini-4-argon")
LLM_THINKING_LEVEL = os.environ.get("THINKING_LEVEL", "MEDIUM")
LLM_TEMPERATURE = float(os.environ.get("TEMPERATURE", 0.2))
LLM_TOP_P = float(os.environ.get("TOP_P", 1.0))
LLM_TOP_K = int(os.environ.get("TOP_K", 40))
LLM_CANDIDATE_COUNT = int(os.environ.get("CANDIDATE_COUNT", 1))
LLM_MAX_OUTPUT_TOKENS = int(os.environ.get("MAX_OUTPUT_TOKENS", 1024))

# Vector Search 2.0 Configuration
VECTOR_SEARCH_COLLECTION_ID = os.environ.get("VECTOR_SEARCH_COLLECTION_ID")
VECTOR_SEARCH_LOCATION = os.environ.get("VECTOR_SEARCH_LOCATION", REGION)
VECTOR_SEARCH_EMBEDDING_FIELD = os.environ.get("VECTOR_SEARCH_EMBEDDING_FIELD",
                                               "text_embedding")
VECTOR_SEARCH_TASK_TYPE = os.environ.get("VECTOR_SEARCH_TASK_TYPE",
                                         "QUESTION_ANSWERING")
VECTOR_SEARCH_TEXT_FIELDS = [
    field.strip()
    for field in os.environ.get("VECTOR_SEARCH_TEXT_FIELDS",
                                "title,description,genre").split(",")
    if field.strip()
]

# Retriever Configuration
RETRIEVER_TOP_K = int(os.environ.get("RETRIEVER_TOP_K", 10))
