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
import time
from typing import Any, Optional
import urllib.parse
import uuid

from google.cloud import firestore
from google.adk.sessions import BaseSessionService, Session
from google.adk.sessions.base_session_service import ListSessionsResponse
from google.adk.events import Event


def _encode_key_part(value: str, field_name: str) -> str:
  if not isinstance(value, str) or not value.strip():
    raise ValueError(f"{field_name} must be a non-empty string.")
  return urllib.parse.quote(value, safe="")


def _build_session_doc_id(app_name: str, user_id: str, session_id: str) -> str:
  encoded = ":".join((
      _encode_key_part(app_name, "app_name"),
      _encode_key_part(user_id, "user_id"),
      _encode_key_part(session_id, "session_id"),
  ))
  if len(encoded.encode("utf-8")) > 500:
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()
  return encoded


def _matches_owner(data: Optional[dict[str, Any]], app_name: str,
                   user_id: Optional[str]) -> bool:
  if not data:
    return False
  stored_app = data.get("app_name") if "app_name" in data else data.get(
      "appName")
  if stored_app != app_name:
    return False
  if user_id is not None:
    stored_user = data.get("user_id") if "user_id" in data else data.get(
        "userId")
    if stored_user != user_id:
      return False
  return True


class FirestoreSessionService(BaseSessionService):

  def __init__(self, project_id: str, collection_name: str = "adk_sessions",
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

  def _get_doc_ref(self, app_name: str, user_id: str, session_id: str):
    doc_id = _build_session_doc_id(app_name, user_id, session_id)
    return self.db.collection(self.collection_name).document(doc_id)

  async def create_session(
      self,
      *,
      app_name: str,
      user_id: str,
      state: Optional[dict[str, Any]] = None,
      session_id: Optional[str] = None,
  ) -> Session:
    _encode_key_part(app_name, "app_name")
    _encode_key_part(user_id, "user_id")
    sid = (session_id.strip()
           if session_id and session_id.strip() else str(uuid.uuid4()))
    session = Session(
        id=sid,
        app_name=app_name,
        user_id=user_id,
        state=state or {},
        last_update_time=time.time(),
    )
    doc_ref = self._get_doc_ref(app_name, user_id, sid)
    # using mode='json' to convert internal types
    data = session.model_dump(mode='json')
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
    doc_ref = self._get_doc_ref(app_name, user_id, session_id)
    doc = await doc_ref.get()
    if not doc.exists:
      return None
    data = doc.to_dict()
    if not _matches_owner(data, app_name, user_id):
      return None
    return Session.model_validate(data)

  async def list_sessions(
      self, *, app_name: str,
      user_id: Optional[str] = None) -> ListSessionsResponse:
    _encode_key_part(app_name, "app_name")
    query = self.db.collection(self.collection_name).where(
        "app_name", "==", app_name)
    if user_id is not None:
      _encode_key_part(user_id, "user_id")
      query = query.where("user_id", "==", user_id)
    docs = await query.get()
    sessions = []
    for doc in docs:
      data = doc.to_dict()
      if _matches_owner(data, app_name, user_id):
        sessions.append(Session.model_validate(data))
    return ListSessionsResponse(sessions=sessions)

  async def delete_session(self, *, app_name: str, user_id: str,
                           session_id: str) -> None:
    doc_ref = self._get_doc_ref(app_name, user_id, session_id)
    doc = await doc_ref.get()
    if not doc.exists:
      return
    data = doc.to_dict()
    if not _matches_owner(data, app_name, user_id):
      return
    await doc_ref.delete()

  async def append_event(self, session: Session, event: Event) -> Event:
    # call super to update the session in memory
    event = await super().append_event(session, event)
    # persist the session
    session.last_update_time = time.time()
    doc_ref = self._get_doc_ref(session.app_name, session.user_id, session.id)
    data = session.model_dump(mode='json')
    await doc_ref.set(data)
    return event
