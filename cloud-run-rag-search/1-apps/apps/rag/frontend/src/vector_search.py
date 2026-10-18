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
import sys
from typing import Any

from google.api_core import exceptions
from google.cloud import vectorsearch_v1

from src import config

logging.basicConfig(
    level=logging.INFO,
    format="%(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)


def _format_value(value: Any) -> str:
  """Formats a DataObject field value for prompt context."""
  if value is None:
    return "None"
  if isinstance(value, list):
    return ",".join(str(v_item).strip() for v_item in value)
  return str(value).strip()


def _format_data_object_for_prompt(data_object: Any) -> str:
  """Converts a Vector Search 2.0 DataObject into a prompt context string."""
  data_fields = dict(data_object.data) if data_object.data else {}
  content_parts = [
      f"{key}: {_format_value(value)}"
      for key, value in sorted(data_fields.items())
  ]
  return "; ".join(content_parts)


def search_similar_documents(query_text: str, num_neighbors: int) -> list[str]:
  """Searches a Vector Search 2.0 collection using Hybrid Search (Semantic + Text + RRF).

  Uses Vector Search 2.0 auto-embeddings for semantic search combined with
  full-text search over configured text fields, ranked via Reciprocal Rank
  Fusion (RRF).

  Args:
      query_text: Natural language query from the user.
      num_neighbors: Number of top matching documents to return.

  Returns:
      A list of formatted document strings from the matching DataObjects.
  """
  if not all([
      config.PROJECT_ID,
      config.VECTOR_SEARCH_LOCATION,
      config.VECTOR_SEARCH_COLLECTION_ID,
  ]):
    logging.warning(
        "Vector Search 2.0 collection is not configured. Skipping document search."
    )
    return []

  parent = (
      f"projects/{config.PROJECT_ID}/locations/{config.VECTOR_SEARCH_LOCATION}"
      f"/collections/{config.VECTOR_SEARCH_COLLECTION_ID}")

  try:
    search_client = vectorsearch_v1.DataObjectSearchServiceClient()
    output_fields = vectorsearch_v1.OutputFields(
        data_fields=["*"],
        metadata_fields=["*"],
    )

    semantic_search = vectorsearch_v1.Search(
        semantic_search=vectorsearch_v1.SemanticSearch(
            search_text=query_text,
            search_field=config.VECTOR_SEARCH_EMBEDDING_FIELD,
            task_type=getattr(
                vectorsearch_v1.EmbeddingTaskType,
                config.VECTOR_SEARCH_TASK_TYPE,
                vectorsearch_v1.EmbeddingTaskType.QUESTION_ANSWERING,
            ),
            top_k=num_neighbors,
            output_fields=output_fields,
        ))

    searches = [semantic_search]
    weights = [1.0]

    if config.VECTOR_SEARCH_TEXT_FIELDS:
      text_search = vectorsearch_v1.Search(
          text_search=vectorsearch_v1.TextSearch(
              search_text=query_text,
              data_field_names=config.VECTOR_SEARCH_TEXT_FIELDS,
              top_k=num_neighbors,
              output_fields=output_fields,
          ))
      searches.append(text_search)
      weights.append(1.0)

    logging.info(
        "Executing Hybrid Search (Semantic + Text with RRF) on '%s' for top %d neighbors.",
        parent,
        num_neighbors,
    )
    request = vectorsearch_v1.BatchSearchDataObjectsRequest(
        parent=parent,
        searches=searches,
        combine=vectorsearch_v1.BatchSearchDataObjectsRequest.
        CombineResultsOptions(
            ranker=vectorsearch_v1.Ranker(
                rrf=vectorsearch_v1.ReciprocalRankFusion(weights=weights)),
            output_fields=output_fields,
            top_k=num_neighbors,
        ),
    )

    response = search_client.batch_search_data_objects(request)
    if not response.results:
      return []

    documents = [
        _format_data_object_for_prompt(item.data_object)
        for item in response.results[0].results
        if item.data_object and item.data_object.data
    ]

    logging.info(
        "Retrieved %d matching documents from Vector Search 2.0 collection.",
        len(documents),
    )
    return documents

  except exceptions.GoogleAPICallError as e:
    logging.error("Vector Search 2.0 API call failed: %s", e, exc_info=True)
    return []
  except Exception as e:
    logging.error(
        "An unexpected error occurred during Vector Search 2.0 query: %s",
        e,
        exc_info=True,
    )
    return []
