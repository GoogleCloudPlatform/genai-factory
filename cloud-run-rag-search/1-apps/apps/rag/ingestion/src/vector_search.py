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
from typing import Any

from google.api_core import exceptions
from google.cloud import vectorsearch_v1

logger = logging.getLogger(__name__)


def upsert_data_objects_to_collection(
    project: str,
    location: str,
    collection_id: str,
    data_objects: list[dict[str, Any]],
) -> None:
  """Upserts a batch of DataObjects into a Vector Search 2.0 collection.

  Vector Search 2.0 collections configured with `vertex_embedding_config`
  automatically generate embeddings from the `data` payload when `vectors` is
  left empty (`{}`).

  Args:
      project: The GCP project ID.
      location: The region where the collection is located.
      collection_id: The ID of the Vector Search 2.0 collection.
      data_objects: A list of dictionaries with `data_object_id` and `data`.
  """
  if not data_objects:
    logger.warning("No data objects provided to upsert.")
    return

  parent = (
      f"projects/{project}/locations/{location}/collections/{collection_id}")
  client = vectorsearch_v1.DataObjectServiceClient()

  logger.info(
      f"Upserting {len(data_objects)} data objects into collection '{parent}'.")

  create_requests = [
      vectorsearch_v1.CreateDataObjectRequest(
          parent=parent,
          data_object_id=item["data_object_id"],
          data_object=vectorsearch_v1.DataObject(
              data=item["data"],
              vectors={},
          ),
      ) for item in data_objects
  ]

  try:
    client.batch_create_data_objects(
        vectorsearch_v1.BatchCreateDataObjectsRequest(
            parent=parent,
            requests=create_requests,
        ))
    logger.info(
        f"Successfully created {len(data_objects)} data objects in '{parent}'.")
    return
  except exceptions.AlreadyExists:
    logger.info(
        "Some or all data objects already exist; falling back to batch update.")
  except Exception as e:
    logger.error(
        f"Failed to batch create data objects in '{parent}'. Error: {e}")
    raise

  update_requests = [
      vectorsearch_v1.UpdateDataObjectRequest(
          data_object=vectorsearch_v1.DataObject(
              name=f"{parent}/dataObjects/{item['data_object_id']}",
              data=item["data"],
              vectors={},
          )) for item in data_objects
  ]

  try:
    client.batch_update_data_objects(
        vectorsearch_v1.BatchUpdateDataObjectsRequest(
            parent=parent,
            requests=update_requests,
        ))
    logger.info(
        f"Successfully updated {len(data_objects)} data objects in '{parent}'.")
  except exceptions.NotFound:
    logger.info(
        "Mixed new and existing data objects detected; upserting individually.")
    for create_req, update_req in zip(create_requests, update_requests,
                                      strict=True):
      try:
        client.create_data_object(create_req)
      except exceptions.AlreadyExists:
        client.update_data_object(update_req)
    logger.info(
        f"Successfully upserted {len(data_objects)} data objects in '{parent}'."
    )
  except Exception as e:
    logger.error(
        f"Failed to batch update data objects in '{parent}'. Error: {e}")
    raise
