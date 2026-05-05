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

import uuid
import time
from typing import Any, Optional

from google.cloud import firestore
from google.adk.sessions import BaseSessionService, Session
from google.adk.sessions.base_session_service import ListSessionsResponse
from google.adk.events import Event


class FirestoreSessionService(BaseSessionService):

  def __init__(self, project_id: str, collection_name: str = "adk_sessions"):
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

  async def create_session(
      self,
      *,
      app_name: str,
      user_id: str,
      state: Optional[dict[str, Any]] = None,
      session_id: Optional[str] = None,
  ) -> Session:
    sid = session_id or str(uuid.uuid4())
    session = Session(
        id=sid,
        app_name=app_name,
        user_id=user_id,
        state=state or {},
        last_update_time=time.time(),
    )
    doc_ref = self.db.collection(self.collection_name).document(sid)
    # using mode='json' to convert internal types
    data = session.model_dump(mode='json', by_alias=True)
    await doc_ref.set(data)
    return session

  async def get_session(
      self,
      *,
      app_name: str,
      user_id: str,
      session_id: str,
      config: Optional[Any] = None,
  ) -> Optional[Session]:
    doc_ref = self.db.collection(self.collection_name).document(session_id)
    doc = await doc_ref.get()
    if not doc.exists:
      return None
    return Session.model_validate(doc.to_dict())

  async def list_sessions(
      self, *, app_name: str,
      user_id: Optional[str] = None) -> ListSessionsResponse:
    query = self.db.collection(self.collection_name).where(
        "app_name", "==", app_name)
    if user_id:
      query = query.where("user_id", "==", user_id)
    docs = await query.get()
    sessions = [Session.model_validate(doc.to_dict()) for doc in docs]
    return ListSessionsResponse(sessions=sessions)

  async def delete_session(self, *, app_name: str, user_id: str,
                           session_id: str) -> None:
    doc_ref = self.db.collection(self.collection_name).document(session_id)
    await doc_ref.delete()

  async def append_event(self, session: Session, event: Event) -> Event:
    # call super to update the session in memory
    event = await super().append_event(session, event)
    # persist the session
    session.last_update_time = time.time()
    doc_ref = self.db.collection(self.collection_name).document(session.id)
    data = session.model_dump(mode='json', by_alias=True)
    await doc_ref.set(data)
    return event
