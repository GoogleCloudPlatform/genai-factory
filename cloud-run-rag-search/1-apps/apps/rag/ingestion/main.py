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

import logging
import os
import re
import sys
from typing import Any

from src import config, storage, vector_search

# --- Configuration Loading and Validation ---
try:
  if not config.PROJECT_ID:
    raise KeyError("PROJECT_ID environment variable must be set.")
  if not config.GCS_SOURCE_BUCKET or not config.GCS_SOURCE_BLOB_NAME:
    raise KeyError(
        "GCS_SOURCE_BUCKET and GCS_SOURCE_BLOB_NAME environment variables must be set."
    )
  if not config.VECTOR_SEARCH_COLLECTION_ID:
    raise KeyError(
        "VECTOR_SEARCH_COLLECTION_ID environment variable must be set.")

except KeyError as e:
  logging.error(f"Missing required environment variable: {e}")
  sys.exit(1)
except ValueError as e:
  logging.error(
      f"Error parsing numeric environment variable (e.g., VECTOR_SEARCH_UPSERT_BATCH_SIZE): {e}"
  )
  sys.exit(1)

# --- Logging Setup ---
logging.basicConfig(
    level=logging.INFO,
    format="%(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)


def format_data_object_id(raw_id: Any) -> str:
  """Formats a record ID into an RFC1035-compliant DataObject ID."""
  sanitized = re.sub(r"[^a-z0-9-]", "-", str(raw_id).strip().lower()).strip("-")
  if not sanitized or not sanitized[0].isalpha():
    sanitized = f"item-{sanitized}" if sanitized else "item-0"
  return sanitized[:63].rstrip("-")


def run_indexer() -> None:
  """Streams data from a GCS JSONL file and upserts DataObjects into Vector Search 2.0."""
  logger.info("Starting Vector Search 2.0 ingestion job...")
  logger.info(f"Project ID: {config.PROJECT_ID}, Region: {config.REGION}")
  logger.info(
      f"GCS source: gs://{config.GCS_SOURCE_BUCKET}/{config.GCS_SOURCE_BLOB_NAME}"
  )
  logger.info(
      f"Vector Search Collection ID: {config.VECTOR_SEARCH_COLLECTION_ID} "
      f"(location: {config.VECTOR_SEARCH_LOCATION})")
  logger.info(f"Upsert batch size: {config.VECTOR_SEARCH_UPSERT_BATCH_SIZE}")

  batch_for_upsert: list[dict[str, Any]] = []
  total_processed_count = 0
  total_upserted_count = 0

  source_iterator = storage.stream_gcs_jsonl_file(
      project_id=config.PROJECT_ID,
      bucket_name=config.GCS_SOURCE_BUCKET,
      blob_name=config.GCS_SOURCE_BLOB_NAME,
  )

  for record in source_iterator:
    total_processed_count += 1

    raw_id = record.get("id")
    if raw_id is None or str(raw_id).strip() == "":
      logger.warning(
          f"Skipping record number {total_processed_count} due to missing 'id' field. Record: {record}"
      )
      continue

    data_object_id = format_data_object_id(raw_id)
    data_payload = {k: v for k, v in record.items() if k != "id"}
    if not data_payload:
      logger.warning(
          f"Skipping record with ID {raw_id} due to empty data payload.")
      continue

    batch_for_upsert.append({
        "data_object_id": data_object_id,
        "data": data_payload,
    })

    if len(batch_for_upsert) >= config.VECTOR_SEARCH_UPSERT_BATCH_SIZE:
      logger.info(
          f"Upserting a batch of {len(batch_for_upsert)} data objects to Vector Search..."
      )
      vector_search.upsert_data_objects_to_collection(
          project=config.PROJECT_ID,
          location=config.VECTOR_SEARCH_LOCATION,
          collection_id=config.VECTOR_SEARCH_COLLECTION_ID,
          data_objects=batch_for_upsert,
      )
      total_upserted_count += len(batch_for_upsert)
      batch_for_upsert = []

  if batch_for_upsert:
    logger.info(
        f"Upserting the final batch of {len(batch_for_upsert)} data objects to Vector Search..."
    )
    vector_search.upsert_data_objects_to_collection(
        project=config.PROJECT_ID,
        location=config.VECTOR_SEARCH_LOCATION,
        collection_id=config.VECTOR_SEARCH_COLLECTION_ID,
        data_objects=batch_for_upsert,
    )
    total_upserted_count += len(batch_for_upsert)

  logger.info("Ingestion job finished.")
  logger.info(
      f"Total records processed from GCS file: {total_processed_count}.")
  logger.info(
      f"Total data objects successfully upserted to Vector Search: {total_upserted_count}."
  )


if __name__ == "__main__":
  job_task_index = os.environ.get("CLOUD_RUN_TASK_INDEX", "N/A")
  job_attempt = os.environ.get("CLOUD_RUN_TASK_ATTEMPT", "N/A")
  logger.info(
      f"Cloud Run Job: Task Index {job_task_index}, Attempt {job_attempt}.")

  try:
    run_indexer()
    logger.info("Indexer run completed successfully.")
    sys.exit(0)
  except SystemExit as e:
    logger.info(f"Indexer run exited with code {e.code}.")
    sys.exit(e.code)
  except Exception as e:
    logger.exception(
        f"Unhandled error during indexer execution on Task {job_task_index}, Attempt {job_attempt}: {e}"
    )
    sys.exit(1)
