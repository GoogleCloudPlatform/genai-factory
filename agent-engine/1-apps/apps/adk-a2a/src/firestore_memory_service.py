# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import time
import uuid

from google.cloud import firestore
from google.adk.memory.base_memory_service import BaseMemoryService, SearchMemoryResponse
from google.adk.memory.memory_entry import MemoryEntry
from google.adk.sessions import Session
from google.genai import types


class FirestoreMemoryService(BaseMemoryService):

  def __init__(self, project_id: str, collection_name: str = "adk_memory"):
    self.project_id = project_id
    self.collection_name = collection_name
    self._db = None
    self._loop = None

  @property
  def db(self):
    import asyncio
    try:
      loop = asyncio.get_running_loop()
    except RuntimeError:
      loop = None
    if self._db is None or self._loop != loop:
      self._db = firestore.AsyncClient(project=self.project_id)
      self._loop = loop
    return self._db

  async def add_session_to_memory(
      self,
      session: Session,
  ):
    # Iterate through session events and store text content
    entries_to_add = []

    for event in session.event_history:
      # Save parts with text
      if event.content and event.content.parts:
        text_parts = [part for part in event.content.parts if part.text]
        if text_parts:
          entries_to_add.append({
              "app_name":
                  session.app_name,
              "user_id":
                  session.user_id,
              "session_id":
                  session.id,
              "author":
                  event.content.role,
              "timestamp":
                  time.time(),
              "content":
                  types.Content(role=event.content.role,
                                parts=text_parts).model_dump(
                                    mode='json', by_alias=True)
          })

    if not entries_to_add:
      return

    # Use a batch to write all entries
    batch = self.db.batch()
    col_ref = self.db.collection(self.collection_name)

    for entry in entries_to_add:
      doc_ref = col_ref.document(str(uuid.uuid4()))
      batch.set(doc_ref, entry)

    await batch.commit()

  async def search_memory(
      self,
      *,
      app_name: str,
      user_id: str,
      query: str,
  ) -> SearchMemoryResponse:
    # A simplistic search by returning all recent memories for the user.
    # In a real implementation, a vector search or keyword indexing should be used.
    # Here we simulate by returning recent user logs as memory entries.
    db_query = (self.db.collection(self.collection_name).where(
        "app_name", "==", app_name).where("user_id", "==", user_id).order_by(
            "timestamp", direction=firestore.Query.DESCENDING).limit(10))
    docs = await db_query.get()

    memories = []
    for doc in docs:
      data = doc.to_dict()
      content_dict = data.get("content")
      if content_dict:
        memories.append(
            MemoryEntry(author=data.get("author"),
                        timestamp=data.get("timestamp"),
                        content=types.Content.model_validate(content_dict)))
    return SearchMemoryResponse(memories=memories)
