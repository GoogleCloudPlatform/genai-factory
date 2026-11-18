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

import hashlib
from typing import Optional
import urllib.parse

from google.cloud import firestore
from a2a.server.tasks.task_store import TaskStore
from a2a.server.context import ServerCallContext
from a2a.types import Task

from .auth import require_authenticated_user, resolve_authenticated_user

_OWNER_ID_FIELD = "_owner_id"


def _encode_key_part(value: str, field_name: str) -> str:
  if not isinstance(value, str) or not value.strip():
    raise ValueError(f"{field_name} must be a non-empty string.")
  return urllib.parse.quote(value, safe="")


def _build_task_doc_id(owner_id: str, task_id: str) -> str:
  encoded = ":".join((
      _encode_key_part(owner_id, "owner_id"),
      _encode_key_part(task_id, "task_id"),
  ))
  if len(encoded.encode("utf-8")) > 500:
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()
  return encoded


class FirestoreTaskStore(TaskStore):

  def __init__(self, project_id: str, collection_name: str = "tasks",
               database: Optional[str] = None):
    self.project_id = project_id
    self.collection_name = collection_name
    self.database = database
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
      self._db = firestore.AsyncClient(project=self.project_id,
                                       database=self.database)
      self._loop = loop
    return self._db

  def _get_doc_ref(self, owner_id: str, task_id: str):
    doc_id = _build_task_doc_id(owner_id, task_id)
    return self.db.collection(self.collection_name).document(doc_id)

  async def save(self, task: Task,
                 context: ServerCallContext | None = None) -> None:
    owner_id = require_authenticated_user(context)
    doc_ref = self._get_doc_ref(owner_id, task.id)
    # Using mode='json' to ensure enums and datetimes are converted to standard types
    data = task.model_dump(mode='json')
    data[_OWNER_ID_FIELD] = owner_id
    await doc_ref.set(data)

  async def get(self, task_id: str,
                context: ServerCallContext | None = None) -> Task | None:
    owner_id = resolve_authenticated_user(context)
    if not owner_id or not isinstance(task_id, str) or not task_id.strip():
      return None
    doc_ref = self._get_doc_ref(owner_id, task_id)
    doc = await doc_ref.get()
    if not doc.exists:
      return None
    data = doc.to_dict()
    if not data or data.get(_OWNER_ID_FIELD) != owner_id:
      return None
    task_payload = {k: v for k, v in data.items() if k != _OWNER_ID_FIELD}
    return Task.model_validate(task_payload)

  async def delete(self, task_id: str,
                   context: ServerCallContext | None = None) -> None:
    owner_id = resolve_authenticated_user(context)
    if not owner_id or not isinstance(task_id, str) or not task_id.strip():
      return
    doc_ref = self._get_doc_ref(owner_id, task_id)
    doc = await doc_ref.get()
    if not doc.exists:
      return
    data = doc.to_dict()
    if not data or data.get(_OWNER_ID_FIELD) != owner_id:
      return
    await doc_ref.delete()
