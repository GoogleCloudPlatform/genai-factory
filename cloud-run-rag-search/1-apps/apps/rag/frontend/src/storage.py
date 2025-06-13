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

import json
import logging
import sys
from typing import Any, List, Dict

from google.cloud import storage as gcs
import google.api_core.exceptions as exceptions

from src import config

# Configure logging
logging.basicConfig(level=logging.INFO,
                    format='%(name)s - %(levelname)s - %(message)s',
                    handlers=[logging.StreamHandler(sys.stdout)])

# In-memory cache for documents. Populated at application startup.
# Format: { "document_id": { "id": "...", "title": "...", ... } }
document_lookup_cache: Dict[str, Dict] = {}


def load_documents_from_gcs_to_memory():
    """
    Downloads a JSONL file from GCS and loads it into an in-memory dictionary.
    This function is called once at application startup.
    Note: This is suitable for datasets that can comfortably fit in the
    Cloud Run instance's memory. For very large datasets, a database
    lookup (e.g., Firestore, Cloud SQL) would be more appropriate.
    """
    global document_lookup_cache
    bucket_name = config.GCS_SOURCE_BUCKET
    blob_name = config.GCS_SOURCE_BLOB_NAME

    if not bucket_name or not blob_name:
        logging.warning(
            "GCS_SOURCE_BUCKET or GCS_SOURCE_BLOB_NAME not set. "
            "Document lookup will be disabled.")
        return

    try:
        logging.info(
            f"Loading documents from gs://{bucket_name}/{blob_name} into memory..."
        )
        storage_client = gcs.Client(project=config.PROJECT_ID)
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)

        with blob.open("r") as f:
            for line in f:
                record = json.loads(line)
                record_id = record.get("id")
                if record_id:
                    # Ensure ID is a string for consistent key lookup
                    document_lookup_cache[str(record_id)] = record
                else:
                    logging.warning(f"Skipping record with missing 'id': {record}")

        logging.info(
            f"Successfully loaded {len(document_lookup_cache)} documents into memory cache."
        )

    except exceptions.NotFound:
        logging.error(f"GCS object gs://{bucket_name}/{blob_name} not found.")
        document_lookup_cache = {}  # Ensure cache is empty on failure
    except Exception as e:
        logging.error(f"Failed to load documents from GCS: {e}", exc_info=True)
        document_lookup_cache = {}


def _format_json_value_for_embedding(value: Any) -> str:
    """
    Formats a JSON value for inclusion in the 'content_to_embed' string.
    This should be identical to the formatting used during ingestion.
    """
    if value is None:
        return "None"
    if isinstance(value, list):
        return ",".join(str(v_item).strip() for v_item in value)
    return str(value).strip()


def _format_record_for_prompt(record: Dict) -> str:
    """
    Converts a record dictionary into a single string for the prompt context.
    This formatting MUST match the logic used in the ingestion pipeline
    to ensure consistency between what was embedded and what is shown to the LLM.
    """
    content_parts = []
    for key, value in record.items():
        if key == "id":
            continue
        formatted_value = _format_json_value_for_embedding(value)
        content_parts.append(f"{key}: {formatted_value}")

    return "; ".join(sorted(content_parts))


def get_documents_by_ids(ids: List[str]) -> List[str]:
    """
    Retrieves the full content for a list of document IDs from the in-memory cache.
    """
    if not document_lookup_cache:
        logging.warning("Document cache is not populated. Cannot retrieve documents.")
        return []

    found_docs = []
    for doc_id in ids:
        record = document_lookup_cache.get(str(doc_id))
        if record:
            formatted_content = _format_record_for_prompt(record)
            found_docs.append(formatted_content)
        else:
            logging.warning(f"Document ID '{doc_id}' not found in cache.")

    return found_docs
