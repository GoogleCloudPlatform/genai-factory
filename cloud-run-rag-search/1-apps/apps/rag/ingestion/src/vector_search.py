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
from typing import List, Dict, Any
from google.cloud.aiplatform import MatchingEngineIndex

logger = logging.getLogger(__name__)


def upsert_datapoints_to_index(
    project: str,
    location: str,
    index_name: str,
    datapoints: List[Dict[str, Any]],
) -> None:
    """
    Upserts a list of datapoints into a Vertex AI Vector Search index.
    This method is suitable for streaming-enabled indexes.

    Args:
        project (str): The GCP project ID.
        location (str): The region where the index is located.
        index_name (str): The ID or full resource name of the Vector Search index.
        datapoints (List[Dict[str, Any]]): A list of datapoint dictionaries.
            Each dict must have 'datapoint_id' and 'feature_vector'.
    """
    if not datapoints:
        logger.warning("No datapoints provided to upsert.")
        return

    logger.info(
        f"Sending {len(datapoints)} datapoints to be upserted into index '{index_name}'."
    )
    try:
        # Initialize the MatchingEngineIndex object
        index = MatchingEngineIndex(index_name=index_name,
                                    project=project,
                                    location=location)

        # Call the method for streaming updates
        index.upsert_datapoints(datapoints=datapoints)

        logger.info(
            f"Successfully sent {len(datapoints)} datapoints to index '{index_name}'."
        )

    except Exception as e:
        logger.error(
            f"Failed to upsert to Vector Search index '{index_name}'. Error: {e}"
        )
        # Depending on the desired behavior, you might want to retry or handle this error.
        # For a batch job, raising the exception will cause the job to fail.
        raise
