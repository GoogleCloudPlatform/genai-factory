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
from typing import Optional, Union, Any

from google.cloud import firestore
from google.adk.artifacts import BaseArtifactService
from google.adk.artifacts.base_artifact_service import ArtifactVersion
from google.genai import types


class FirestoreArtifactService(BaseArtifactService):

  def __init__(self, project_id: str, collection_name: str = "adk_artifacts"):
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

  def _get_doc_ref(self, app_name: str, user_id: str, session_id: Optional[str],
                   filename: str):
    sid = session_id if session_id else "user_scoped"
    doc_id = f"{app_name}_{user_id}_{sid}_{filename}"
    return self.db.collection(self.collection_name).document(doc_id)

  async def save_artifact(
      self,
      *,
      app_name: str,
      user_id: str,
      filename: str,
      artifact: Union[types.Part, dict[str, Any]],
      session_id: Optional[str] = None,
      custom_metadata: Optional[dict[str, Any]] = None,
  ) -> int:
    doc_ref = self._get_doc_ref(app_name, user_id, session_id, filename)

    if isinstance(artifact, types.Part):
      part_dict = artifact.model_dump(mode='json', by_alias=True)
    else:
      part_dict = artifact

    meta = custom_metadata or {}

    @firestore.async_transactional
    async def append_artifact_version(transaction, ref):
      snapshot = await ref.get(transaction=transaction)
      if snapshot.exists:
        data = snapshot.to_dict()
        versions = data.get("versions", [])
      else:
        versions = []

      new_version = len(versions)

      version_data = {
          "version":
              new_version,
          "part":
              part_dict,
          "custom_metadata":
              meta,
          "create_time":
              time.time(),
          "canonical_uri":
              f"firestore://{self.collection_name}/{doc_ref.id}/{new_version}",
          "mime_type":
              None
      }

      versions.append(version_data)

      transaction.set(
          ref, {
              "app_name": app_name,
              "user_id": user_id,
              "session_id": session_id,
              "filename": filename,
              "versions": versions
          })
      return new_version

    transaction = self.db.transaction()
    return await append_artifact_version(transaction, doc_ref)

  async def load_artifact(
      self,
      *,
      app_name: str,
      user_id: str,
      filename: str,
      session_id: Optional[str] = None,
      version: Optional[int] = None,
  ) -> Optional[types.Part]:
    doc_ref = self._get_doc_ref(app_name, user_id, session_id, filename)
    snapshot = await doc_ref.get()
    if not snapshot.exists:
      return None
    data = snapshot.to_dict()
    versions = data.get("versions", [])
    if not versions:
      return None

    if version is None:
      version = len(versions) - 1

    if version < 0 or version >= len(versions):
      return None

    artifact_dict = versions[version].get("part", {})
    return types.Part.model_validate(artifact_dict)

  async def list_artifact_keys(self, *, app_name: str, user_id: str,
                               session_id: Optional[str] = None) -> list[str]:
    query = (self.db.collection(self.collection_name).where(
        "app_name", "==", app_name).where("user_id", "==", user_id))
    if session_id is not None:
      query = query.where("session_id", "==", session_id)

    docs = await query.get()
    return [
        doc.to_dict().get("filename")
        for doc in docs
        if doc.to_dict().get("filename")
    ]

  async def delete_artifact(self, *, app_name: str, user_id: str, filename: str,
                            session_id: Optional[str] = None) -> None:
    doc_ref = self._get_doc_ref(app_name, user_id, session_id, filename)
    await doc_ref.delete()

  async def list_versions(self, *, app_name: str, user_id: str, filename: str,
                          session_id: Optional[str] = None) -> list[int]:
    doc_ref = self._get_doc_ref(app_name, user_id, session_id, filename)
    snapshot = await doc_ref.get()
    if not snapshot.exists:
      return []
    data = snapshot.to_dict()
    versions = data.get("versions", [])
    return list(range(len(versions)))

  async def list_artifact_versions(
      self,
      *,
      app_name: str,
      user_id: str,
      filename: str,
      session_id: Optional[str] = None,
  ) -> list[ArtifactVersion]:
    doc_ref = self._get_doc_ref(app_name, user_id, session_id, filename)
    snapshot = await doc_ref.get()
    if not snapshot.exists:
      return []
    data = snapshot.to_dict()
    versions = data.get("versions", [])

    result = []
    for v in versions:
      result.append(
          ArtifactVersion(version=v.get("version", 0),
                          canonical_uri=v.get("canonical_uri", ""),
                          custom_metadata=v.get("custom_metadata", {}),
                          create_time=v.get("create_time",
                                            0), mime_type=v.get("mime_type")))
    return result

  async def get_artifact_version(
      self,
      *,
      app_name: str,
      user_id: str,
      filename: str,
      session_id: Optional[str] = None,
      version: Optional[int] = None,
  ) -> Optional[ArtifactVersion]:
    versions = await self.list_artifact_versions(app_name=app_name,
                                                 user_id=user_id,
                                                 filename=filename,
                                                 session_id=session_id)
    if not versions:
      return None

    if version is None:
      return versions[-1]

    if version < 0 or version >= len(versions):
      return None

    return versions[version]
