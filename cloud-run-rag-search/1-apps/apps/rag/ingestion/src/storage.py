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

import logging
import json
from typing import Generator, Dict, Any, Optional
from google.cloud import storage

logger = logging.getLogger(__name__)


def stream_gcs_jsonl_file(bucket_name: str,
                          blob_name: str,
                          project_id: Optional[str] = None
                          ) -> Generator[Dict[str, Any], None, None]:
    """
    Streams a JSONL file from GCS and yields each line as a parsed JSON object.
    This is memory-efficient for large files.

    Args:
        bucket_name (str): The name of the GCS bucket.
        blob_name (str): The name of the object (file) in GCS.
        project_id (str, optional): The GCP project ID. Defaults to None.

    Yields:
        A dictionary parsed from a line in the JSONL file.
    """
    try:
        storage_client = storage.Client(project=project_id)
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)

        logger.info(f"Streaming file gs://{bucket_name}/{blob_name}...")
        with blob.open("rt", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    try:
                        yield json.loads(line)
                    except json.JSONDecodeError:
                        logger.warning(
                            f"Skipping malformed JSON line: {line.strip()}")
    except Exception as e:
        logger.error(
            f"Failed to stream file 'gs://{bucket_name}/{blob_name}'. Error: {e}"
        )
        raise
