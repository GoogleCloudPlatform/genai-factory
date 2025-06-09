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
from google.cloud import storage

logger = logging.getLogger(__name__)


def upload_file_to_gcs(
    local_file_path: str,
    bucket_name: str,
    destination_blob_name: str,
    project_id: str | None = None,
):
    """
    Uploads a local file to a GCS bucket.

    Args:
        local_file_path (str): Path to the local file to upload.
        bucket_name (str): The name of the GCS bucket.
        destination_blob_name (str): The desired name of the object in GCS.
        project_id (str, optional): The GCP project ID. Defaults to None.
    """
    try:
        storage_client = storage.Client(project=project_id)
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)

        logger.info(
            f"Uploading local file '{local_file_path}' to gs://{bucket_name}/{destination_blob_name}..."
        )
        blob.upload_from_filename(local_file_path, content_type="application/jsonl")
        logger.info(
            f"Successfully uploaded file to gs://{bucket_name}/{destination_blob_name}"
        )

    except Exception as e:
        logger.error(
            f"Failed to upload file '{local_file_path}' to GCS bucket '{bucket_name}'. Error: {e}"
        )
        # Reraise the exception to halt the job if the final upload fails.
        raise
