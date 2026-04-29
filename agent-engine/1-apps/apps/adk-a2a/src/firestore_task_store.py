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

from google.cloud import firestore
from a2a.server.tasks.task_store import TaskStore
from a2a.server.context import ServerCallContext
from a2a.types import Task


class FirestoreTaskStore(TaskStore):

  def __init__(self, project_id: str, collection_name: str = "tasks"):
    self.db = firestore.AsyncClient(project=project_id)
    self.collection_name = collection_name

  async def save(self, task: Task,
                 context: ServerCallContext | None = None) -> None:
    doc_ref = self.db.collection(self.collection_name).document(task.id)
    # Using mode='json' to ensure enums and datetimes are converted to standard types
    data = task.model_dump(mode='json')
    await doc_ref.set(data)

  async def get(self, task_id: str,
                context: ServerCallContext | None = None) -> Task | None:
    doc_ref = self.db.collection(self.collection_name).document(task_id)
    doc = await doc_ref.get()
    if doc.exists:
      return Task.model_validate(doc.to_dict())
    return None

  async def delete(self, task_id: str,
                   context: ServerCallContext | None = None) -> None:
    doc_ref = self.db.collection(self.collection_name).document(task_id)
    await doc_ref.delete()
