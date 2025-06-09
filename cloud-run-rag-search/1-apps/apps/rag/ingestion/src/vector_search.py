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
from typing import Optional

from google.cloud.aiplatform import MatchingEngineIndex

logger = logging.getLogger(__name__)


def update_index_embeddings(
    project: str,
    location: str,
    index_name: str,
    gcs_uri: str,
    is_complete_overwrite: Optional[bool] = None,
) -> None:
    """
    Update a Vertex AI Vector Search index with embeddings from a GCS file.

    Args:
        project (str): The GCP project ID.
        location (str): The region where the index is located.
        index_name (str): The ID or full resource name of the Vector Search index.
        gcs_uri (str): The GCS URI of the JSONL file containing the embeddings.
        is_complete_overwrite (bool, optional): If True, replaces the entire
            index content. If False, upserts the data. Defaults to None.
    """
    logger.info(f"Starting Vector Search index update for index '{index_name}'.")
    logger.info(f"  - GCS source: {gcs_uri}")
    logger.info(f"  - Project: {project}, Location: {location}")
    logger.info(f"  - Complete Overwrite: {is_complete_overwrite}")

    try:
        index = MatchingEngineIndex(index_name=index_name, project=project, location=location)

        index.update_embeddings(
            contents_delta_uri=gcs_uri, is_complete_overwrite=is_complete_overwrite
        )
        logger.info(f"Successfully triggered update for index '{index_name}'. The update process will run asynchronously in Vertex AI.")
    except Exception as e:
        logger.error(f"Failed to update Vector Search index '{index_name}'. Error: {e}")
        raise
