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

import json
import os
import logging

import markdown
import frontmatter
import re
import requests
import google.auth
import google.auth.transport.requests
from rich.progress import track
from google.cloud import storage

logger = logging.getLogger(__name__)


def process_data_store_documents(source_dir: str,
                                 target_dir: str,
                                 gcs_bucket_folder_path: str,
                                 ingest_to_data_store: str = None) -> None:
    """
        Preprocesses Markdown files for Data Store ingestion.

        Converts Markdown files to HTML, extracts titles, generates a JSONL manifest,
        and optionally uploads the files to a GCS bucket.

        Args:
            source_dir: Path to the source folder containing Markdown (.md) files.
            target_dir: Path to the destination folder where HTML files
                                    and the JSONL manifest will be placed.
            gcs_bucket_folder_path: Google Cloud Storage bucket folder path
                                    (e.g., "gs://my-bucket/my/path/").
            ingest_to_data_store: Full resource name of the Data Store to ingest documents into.
                                  If provided, triggers the import operation.

        Raises:
            FileNotFoundError: If the source folder does not exist.
            ValueError: If the GCS bucket path does not start with 'gs://'.
            Exception: For errors during GCS upload.
        """

    # --- 1. Input Validation and Setup ---
    if not os.path.isdir(source_dir):
        raise FileNotFoundError(
            f"Error: Source folder not found: '{source_dir}'")

    os.makedirs(target_dir, exist_ok=True)
    logger.debug(f"Destination folder ensured: '{target_dir}'")

    if not gcs_bucket_folder_path.startswith("gs://"):
        raise ValueError(
            f"Error: GCS bucket path must start with 'gs://'. Got: '{gcs_bucket_folder_path}'"
        )

    gcs_bucket_folder_path = f"{gcs_bucket_folder_path.rstrip('/')}/"

    # Parse GCS path into bucket name and blob prefix
    # Example: "gs://my-bucket/my/path/" -> bucket="my-bucket", prefix="my/path/"
    # Example: "gs://my-bucket/" -> bucket="my-bucket", prefix=""
    gcs_path_components = gcs_bucket_folder_path[len("gs://"):].split('/', 1)
    gcs_bucket_name = gcs_path_components[0]
    gcs_blob_prefix = gcs_path_components[1] if len(
        gcs_path_components) > 1 else ""

    # Ensure blob prefix ends with a slash if it's not empty, indicating a folder path
    if gcs_blob_prefix and not gcs_blob_prefix.endswith('/'):
        gcs_blob_prefix += '/'

    logger.info(
        f"Parsed GCS path: Bucket='{gcs_bucket_name}', Blob Prefix='{gcs_blob_prefix}'"
    )

    jsonl_entries = []
    local_files_to_upload = [
    ]  # List to keep track of local file paths that need to be uploaded

    # --- 2. Process Markdown Files ---
    logger.info("\nStarting Markdown file processing...")
    markdown_files_found = False
    for filename in track(os.listdir(source_dir)):
        if not filename.endswith(".md"):
            continue

        markdown_files_found = True
        md_filepath = os.path.join(source_dir, filename)
        base_name = os.path.splitext(filename)[
            0]  # filename without .md extension
        html_filename = f"{base_name}.html"
        html_filepath = os.path.join(target_dir, html_filename)

        logger.info(f"  Processing '{filename}'...")

        try:
            # Parse Front Matter
            post = frontmatter.load(md_filepath)
            raw_metadata = post.metadata
            md_content = post.content

            # Construct structData
            # Requirement: "includes the title an an optional dict of additional metadata. If present, they should all go in the "structData" field"
            struct_data = {}

            # 1. Add title
            title = raw_metadata.get('title')
            if title:
                struct_data['title'] = title

            # 2. Add contents of 'metadata' dict
            additional_metadata = raw_metadata.get('metadata')
            if isinstance(additional_metadata, dict):
                struct_data.update(additional_metadata)

            # Convert Markdown content to HTML
            html_content = markdown.markdown(md_content)

            # Save HTML file to destination folder
            with open(html_filepath, 'w', encoding='utf-8') as f:
                f.write(html_content)
            logger.info(
                f"    - Converted to HTML and saved: '{html_filepath}'")
            local_files_to_upload.append(html_filepath)

            # Prepare JSONL entry
            # The URI for Discovery Engine must point to the *final GCS location*
            gcs_document_uri = f"{gcs_bucket_folder_path}{html_filename}"

            jsonl_entry = {
                "id": base_name,
                "structData": struct_data,
                "content": {
                    "mimeType": "text/html",
                    "uri": gcs_document_uri
                }
            }
            jsonl_entries.append(jsonl_entry)
            logger.info(
                f"    - Prepared JSONL entry for ID: '{base_name}' (Title: '{title}')"
            )

        except Exception as e:
            logger.error(f"  Error processing '{filename}': {e}. Skipping.")
            continue

    if not markdown_files_found:
        logger.warning("No Markdown files (.md) found in the source folder.")

    # --- 3. Generate JSONL Manifest ---
    jsonl_output_filename = "documents.jsonl"
    jsonl_output_path = os.path.join(target_dir, jsonl_output_filename)

    with open(jsonl_output_path, 'w', encoding='utf-8') as f:
        for entry in jsonl_entries:
            f.write(json.dumps(entry) + '\n')
    logger.info(
        f"\nGenerated JSONL manifest: '{jsonl_output_path}' with {len(jsonl_entries)} entries."
    )
    local_files_to_upload.append(
        jsonl_output_path)  # Add JSONL itself to upload list

    # --- 4. Upload to GCS ---
    logger.info(
        f"\nUploading generated files to GCS bucket: '{gcs_bucket_folder_path}'..."
    )
    storage_client = storage.Client()
    bucket = storage_client.bucket(gcs_bucket_name)

    for local_file_path in track(local_files_to_upload):
        # Construct the blob path in GCS
        # Example: /tmp/dest/doc1.html -> doc1.html
        # Example: /tmp/dest/documents.jsonl -> documents.jsonl
        relative_path_from_dest = os.path.relpath(local_file_path, target_dir)
        gcs_blob_name = gcs_blob_prefix + relative_path_from_dest

        blob = bucket.blob(gcs_blob_name)
        blob.upload_from_filename(local_file_path)
        print(
            f"  Uploaded '{local_file_path}' to 'gs://{gcs_bucket_name}/{gcs_blob_name}'"
        )

    # --- 5. Trigger Ingestion (if ingest_to_data_store is provided) ---
    if ingest_to_data_store:
        logger.info(
            f"\nTriggering ingestion to Data Store: '{ingest_to_data_store}'..."
        )

        # The URI for ingestion is the JSONL manifest location in GCS
        # We already constructed gcs_blob_prefix which ends with / if not empty
        # and we know the jsonl filename is jsonl_output_filename

        # We need the full GCS URI of the JSONL file
        # gcs_bucket_folder_path was ensured to end with /
        gcs_jsonl_uri = f"{gcs_bucket_folder_path}{jsonl_output_filename}"

        try:
            import_documents(ingest_to_data_store, gcs_jsonl_uri)
            logger.info("  Ingestion request successfully submitted.")
        except Exception as e:
            logger.error(f"  Error submitting ingestion request: {e}")
            # We might not want to raise here to avoid failing the whole build if just ingestion fails?
            # But usually for a deployment script failure is better.
            raise e


def import_documents(full_data_store_name: str, gcs_uri: str) -> None:
    """
    Imports documents into a Discovery Engine Data Store from a GCS source.

    Args:
        full_data_store_name: The full resource name of the data store.
                              Format: projects/{project}/locations/{location}/collections/{collection}/dataStores/{dataStore}
        gcs_uri: The GCS URI of the source data (e.g., "gs://bucket/path/documents.jsonl").
    """

    # Extract location from full_data_store_name
    # Pattern: projects/.../locations/{location}/...
    match = re.search(r'/locations/([^/]+)/', full_data_store_name)
    if not match:
        raise ValueError(
            f"Could not extract location from data store name: '{full_data_store_name}'"
        )

    location = match.group(1)

    # Construct API Endpoint
    if location == "global":
        api_endpoint = f"https://discoveryengine.googleapis.com/v1/{full_data_store_name}/branches/0/documents:import"
    else:
        api_endpoint = f"https://{location}-discoveryengine.googleapis.com/v1/{full_data_store_name}/branches/0/documents:import"

    logger.debug(f"Import API Endpoint: {api_endpoint}")

    # Authentication
    credentials, project = google.auth.default()
    auth_req = google.auth.transport.requests.Request()
    credentials.refresh(auth_req)
    access_token = credentials.token

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "X-Goog-User-Project": project
    }

    # Request Body
    body = {
        "gcsSource": {
            "inputUris": [gcs_uri],
            "dataSchema":
            "document"  # OR "custom" depending on setup, but typically "document" for Unstructured/structured
        },
        "reconciliationMode": "FULL"
    }

    # Make Request
    response = requests.post(api_endpoint, headers=headers, json=body)

    if response.status_code != 200:
        logger.error(
            f"Import failed with status code {response.status_code}: {response.text}"
        )
        response.raise_for_status()

    logger.info(
        f"Import started. Response: {json.dumps(response.json(), indent=2)}")
