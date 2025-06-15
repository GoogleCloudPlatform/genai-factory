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
import sys
from typing import List

from google.cloud import aiplatform
import google.api_core.exceptions as exceptions

from src import config

# Note: You may need to install the library:
# pip install google-cloud-aiplatform

# Configure logging
logging.basicConfig(
    level=logging.INFO,  # Set the default logging level
    format='%(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)])


def find_similar_document_ids(query_embedding: List[float],
                              num_neighbors: int) -> List[str]:
    """
    Searches for documents with embeddings similar to the query_embedding
    using Vertex AI Vector Search and returns their IDs.

    Args:
        query_embedding: A list of floats representing the query embedding.
        num_neighbors: The number of nearest neighbors to retrieve.

    Returns:
        A list of strings, where each string is the ID of a similar document.
    """
    if not all([
            config.VECTOR_SEARCH_INDEX_ENDPOINT_NAME,
            config.VECTOR_SEARCH_DEPLOYED_INDEX_ID
    ]):
        logging.warning(
            "Vector Search is not configured. Skipping document search.")
        return []

    try:
        logging.info("Initializing Vertex AI Platform client.")
        aiplatform.init(project=config.PROJECT_ID, location=config.REGION)

        index_endpoint = aiplatform.MatchingEngineIndexEndpoint(
            index_endpoint_name=config.VECTOR_SEARCH_INDEX_ENDPOINT_NAME)

        index_endpoint.private_service_connect_ip_address = config.VECTOR_SEARCH_ENDPOINT_IP_ADDRESS
        logging.info(
            f"Using private service connect with IP: {config.VECTOR_SEARCH_ENDPOINT_IP_ADDRESS}"
        )

        logging.info(
            f"Querying Vector Search index for {num_neighbors} neighbors.")

        # The match method expects a list of queries.
        # We are sending a single query.
        response = index_endpoint.match(
            deployed_index_id=config.VECTOR_SEARCH_DEPLOYED_INDEX_ID,
            queries=[query_embedding],
            num_neighbors=num_neighbors)

        # The response is a list of lists of MatchNeighbor objects.
        neighbors = response[0] if response else []

        # Return only the IDs of the neighbors.
        # The calling function will be responsible for looking up the content.
        document_ids = [neighbor.id for neighbor in neighbors]

        logging.info(
            f"Retrieved {len(document_ids)} similar document IDs from Vector Search."
        )
        return document_ids

    except exceptions.GoogleAPICallError as e:
        logging.error(f"Vector Search API call failed: {e}", exc_info=True)
        return []
    except Exception as e:
        logging.error(
            f"An unexpected error occurred during Vector Search query: {e}",
            exc_info=True)
        return []
