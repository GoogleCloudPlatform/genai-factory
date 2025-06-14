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
import threading
import time
from typing import Any, List, Dict

from google.cloud import storage as gcs
import google.api_core.exceptions as exceptions

from src import config

# Configure logging
logging.basicConfig(level=logging.INFO,
                    format='%(name)s - %(levelname)s - %(message)s',
                    handlers=[logging.StreamHandler(sys.stdout)])

# --- In-memory cache with TTL logic ---
_document_lookup_cache: Dict[str, Dict] = {}
_cache_load_time: float = 0.0
_cache_lock = threading.Lock()


def _load_documents_from_gcs():
    """
    Internal function to download a JSONL file from GCS and load it into
    the in-memory dictionary. This is the slow operation.
    """
    global _document_lookup_cache, _cache_load_time
    bucket_name = config.GCS_SOURCE_BUCKET
    blob_name = config.GCS_SOURCE_BLOB_NAME

    if not bucket_name:
        logging.warning("GCS_SOURCE_BUCKET not set. "
                        "Document lookup will be disabled.")
        return

    try:
        logging.info(
            f"Refreshing document cache from gs://{bucket_name}/{blob_name}..."
        )
        storage_client = gcs.Client(project=config.PROJECT_ID)
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)

        new_cache = {}
        with blob.open("r") as f:
            for line in f:
                record = json.loads(line)
                record_id = record.get("id")
                if record_id:
                    # Ensure ID is a string for consistent key lookup
                    new_cache[str(record_id)] = record
                else:
                    logging.warning(
                        f"Skipping record with missing 'id': {record}")

        _document_lookup_cache = new_cache
        _cache_load_time = time.time()
        logging.info(
            f"Successfully loaded {len(_document_lookup_cache)} documents into memory cache."
        )

    except exceptions.NotFound:
        logging.error(f"GCS object gs://{bucket_name}/{blob_name} not found.")
        _document_lookup_cache = {}
    except Exception as e:
        logging.error(f"Failed to load documents from GCS: {e}", exc_info=True)
        _document_lookup_cache = {}


def _is_cache_stale() -> bool:
    """Checks if the cache is empty or if its TTL has expired."""
    if not _document_lookup_cache:
        return True
    return (time.time() - _cache_load_time) > config.DOCUMENT_CACHE_TTL_SECONDS


def get_documents_by_ids(ids: List[str]) -> List[str]:
    """
    Retrieves the full content for a list of document IDs.
    If the cache is stale, it safely triggers a refresh from GCS.
    """
    if _is_cache_stale():
        # Use a lock to prevent multiple concurrent requests from all
        # trying to refresh the cache at once (cache stampede problem).
        with _cache_lock:
            # Double-check if another thread already refreshed the cache
            # while this thread was waiting for the lock.
            if _is_cache_stale():
                _load_documents_from_gcs()

    if not _document_lookup_cache:
        logging.warning(
            "Document cache is not populated. Cannot retrieve documents.")
        return []

    found_docs = []
    for doc_id in ids:
        record = _document_lookup_cache.get(str(doc_id))
        if record:
            formatted_content = _format_record_for_prompt(record)
            found_docs.append(formatted_content)
        else:
            logging.warning(f"Document ID '{doc_id}' not found in cache.")

    return found_docs


def get_cache_status() -> str:
    """Returns a string describing the current state of the cache."""
    if _document_lookup_cache:
        age_seconds = int(time.time() - _cache_load_time)
        return f"Loaded {len(_document_lookup_cache)} documents ({age_seconds}s ago)"
    return "Not loaded or empty"


def _format_json_value_for_embedding(value: Any) -> str:
    """Formats a JSON value for inclusion in the 'content_to_embed' string."""
    if value is None:
        return "None"
    if isinstance(value, list):
        return ",".join(str(v_item).strip() for v_item in value)
    return str(value).strip()


def _format_record_for_prompt(record: Dict) -> str:
    """
    Converts a record dictionary into a single string for the prompt context.
    This formatting MUST match the logic used in the ingestion pipeline.
    """
    content_parts = []
    for key, value in record.items():
        if key == "id":
            continue
        formatted_value = _format_json_value_for_embedding(value)
        content_parts.append(f"{key}: {formatted_value}")
    return "; ".join(sorted(content_parts))
