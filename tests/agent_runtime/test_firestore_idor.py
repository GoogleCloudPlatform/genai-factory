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
"""Regression unit tests for agent-runtime Firestore session/task isolation and caller auth."""

from abc import ABC, abstractmethod
import asyncio
import copy
import importlib.util
from pathlib import Path
import sys
import types as py_types
from typing import Any, Optional
from unittest.mock import MagicMock, patch

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
ADK_A2A_DIR = REPO_ROOT / "agent-runtime/1-apps/apps/adk-a2a"
ADK_DIR = REPO_ROOT / "agent-runtime/1-apps/apps/adk"


class FakeSnapshot:

  def __init__(self, doc_id: str, data: Optional[dict[str, Any]]):
    self.id = doc_id
    self._data = copy.deepcopy(data) if data is not None else None

  @property
  def exists(self) -> bool:
    return self._data is not None

  def to_dict(self) -> Optional[dict[str, Any]]:
    return copy.deepcopy(self._data) if self._data is not None else None


class FakeDocumentRef:

  def __init__(self, store: dict[str, dict[str, Any]], doc_id: str):
    if not doc_id or doc_id in (".", "..") or "/" in doc_id:
      raise ValueError(f"Unsafe Firestore document ID: {doc_id!r}")
    if len(doc_id.encode("utf-8")) > 1500:
      raise ValueError("Document ID exceeds Firestore 1500-byte limit")
    self._store = store
    self.id = doc_id

  async def set(self, data: dict[str, Any]) -> None:
    self._store[self.id] = copy.deepcopy(data)

  async def get(self, transaction: Any = None) -> FakeSnapshot:
    del transaction
    return FakeSnapshot(self.id, self._store.get(self.id))

  async def delete(self) -> None:
    self._store.pop(self.id, None)


class FakeQuery:

  def __init__(self, store: dict[str, dict[str, Any]],
               filters: Optional[list[tuple[str, str, Any]]] = None):
    self._store = store
    self._filters = list(filters or [])

  def where(self, field: str, op: str, value: Any) -> "FakeQuery":
    return FakeQuery(self._store, self._filters + [(field, op, value)])

  async def get(self) -> list[FakeSnapshot]:
    results = []
    for doc_id, data in self._store.items():
      matched = True
      for field, op, value in self._filters:
        assert op == "=="
        if data.get(field) != value:
          matched = False
          break
      if matched:
        results.append(FakeSnapshot(doc_id, data))
    return results


class FakeCollection:

  def __init__(self, store: dict[str, dict[str, Any]]):
    self._store = store

  def document(self, doc_id: str) -> FakeDocumentRef:
    return FakeDocumentRef(self._store, doc_id)

  def where(self, field: str, op: str, value: Any) -> FakeQuery:
    return FakeQuery(self._store, [(field, op, value)])


class FakeFirestoreClient:

  def __init__(self) -> None:
    self.collections: dict[str, dict[str, dict[str, Any]]] = {}

  def collection(self, name: str) -> FakeCollection:
    return FakeCollection(self.collections.setdefault(name, {}))


def _ensure_runtime_sdk_stubs(monkeypatch: pytest.MonkeyPatch) -> None:
  """Installs minimal ADK/A2A/Vertex stubs when running in root CI venv."""
  try:
    import a2a.auth.user  # noqa: F401
    import google.adk.sessions  # noqa: F401
    import google.auth.transport.requests  # noqa: F401
    import google.cloud.firestore  # noqa: F401
    import starlette.requests  # noqa: F401
    import vertexai.preview.reasoning_engines  # noqa: F401
    return
  except ImportError:
    pass

  def _ensure_pkg(name: str) -> py_types.ModuleType:
    if name in sys.modules:
      return sys.modules[name]
    parent_name, _, child_name = name.rpartition(".")
    mod = py_types.ModuleType(name)
    mod.__path__ = []  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, name, mod)
    if parent_name:
      parent = _ensure_pkg(parent_name)
      setattr(parent, child_name, mod)
    return mod

  # google.cloud.firestore
  firestore_mod = _ensure_pkg("google.cloud.firestore")
  firestore_mod.AsyncClient = MagicMock()  # type: ignore[attr-defined]
  firestore_mod.Query = py_types.SimpleNamespace(
      DESCENDING="DESCENDING")  # type: ignore[attr-defined]
  firestore_mod.async_transactional = lambda fn: fn  # type: ignore[attr-defined]

  # google.auth & google.oauth2.id_token
  transport_mod = _ensure_pkg("google.auth.transport")

  class _StubTransportRequest:
    pass

  class _StubTransportResponse:
    status = 200
    data = b"{}"

  transport_mod.Request = _StubTransportRequest  # type: ignore[attr-defined]
  transport_mod.Response = _StubTransportResponse  # type: ignore[attr-defined]

  ga_requests_mod = _ensure_pkg("google.auth.transport.requests")

  class _StubGoogleAuthRequest(_StubTransportRequest):

    def __call__(self, *args: Any, **kwargs: Any) -> _StubTransportResponse:
      return _StubTransportResponse()

  ga_requests_mod.Request = _StubGoogleAuthRequest  # type: ignore[attr-defined]

  id_token_mod = _ensure_pkg("google.oauth2.id_token")
  id_token_mod.verify_oauth2_token = MagicMock()  # type: ignore[attr-defined]
  id_token_mod.verify_token = MagicMock()  # type: ignore[attr-defined]

  # google.genai.types
  genai_types_mod = _ensure_pkg("google.genai.types")

  class _StubPart:

    def __init__(self, text: Optional[str] = None, **kwargs: Any):
      self.text = text
      self._extra = kwargs

    def model_dump(self, **kwargs: Any) -> dict[str, Any]:
      del kwargs
      return {"text": self.text, **self._extra}

    @classmethod
    def model_validate(cls, data: dict[str, Any]) -> "_StubPart":
      return cls(**data)

  class _StubContent:

    def __init__(self, role: Optional[str] = None,
                 parts: Optional[list[Any]] = None):
      self.role = role
      self.parts = parts or []

    def model_dump(self, **kwargs: Any) -> dict[str, Any]:
      del kwargs
      return {
          "role":
              self.role,
          "parts": [
              p.model_dump() if hasattr(p, "model_dump") else p
              for p in self.parts
          ],
      }

    @classmethod
    def model_validate(cls, data: dict[str, Any]) -> "_StubContent":
      return cls(role=data.get("role"), parts=data.get("parts"))

  class _StubThinkingConfig:

    def __init__(self, **kwargs: Any):
      self.kwargs = kwargs

  class _StubGenerateContentConfig:

    def __init__(self, **kwargs: Any):
      self.kwargs = kwargs

  genai_types_mod.Part = _StubPart  # type: ignore[attr-defined]
  genai_types_mod.Content = _StubContent  # type: ignore[attr-defined]
  genai_types_mod.ThinkingConfig = _StubThinkingConfig  # type: ignore[attr-defined]
  genai_types_mod.GenerateContentConfig = _StubGenerateContentConfig  # type: ignore[attr-defined]

  # google.adk.*
  adk_mod = _ensure_pkg("google.adk")
  adk_events_mod = _ensure_pkg("google.adk.events")

  class _StubEvent:

    def __init__(self, content: Any = None, final: bool = True):
      self.content = content
      self._final = final

    def is_final_response(self) -> bool:
      return self._final

  adk_events_mod.Event = _StubEvent  # type: ignore[attr-defined]

  adk_sessions_mod = _ensure_pkg("google.adk.sessions")
  adk_base_ss_mod = _ensure_pkg("google.adk.sessions.base_session_service")

  class _StubSession:

    def __init__(self, id: str, app_name: str, user_id: str,
                 state: Optional[dict[str, Any]] = None,
                 last_update_time: float = 0.0,
                 events: Optional[list[Any]] = None):
      self.id = id
      self.app_name = app_name
      self.user_id = user_id
      self.state = dict(state or {})
      self.last_update_time = last_update_time
      self.events = list(events or [])
      self.event_history = self.events

    def model_dump(self, **kwargs: Any) -> dict[str, Any]:
      del kwargs
      return {
          "id": self.id,
          "app_name": self.app_name,
          "user_id": self.user_id,
          "state": copy.deepcopy(self.state),
          "last_update_time": self.last_update_time,
          "events": list(self.events),
      }

    @classmethod
    def model_validate(cls, data: dict[str, Any]) -> "_StubSession":
      return cls(
          id=data["id"],
          app_name=data["app_name"],
          user_id=data["user_id"],
          state=data.get("state"),
          last_update_time=data.get("last_update_time", 0.0),
          events=data.get("events"),
      )

  class _StubListSessionsResponse:

    def __init__(self, sessions: Optional[list[_StubSession]] = None):
      self.sessions = list(sessions or [])

  class _StubBaseSessionService:

    async def append_event(self, session: _StubSession, event: Any) -> Any:
      session.events.append(event)
      return event

  adk_sessions_mod.Session = _StubSession  # type: ignore[attr-defined]
  adk_sessions_mod.BaseSessionService = _StubBaseSessionService  # type: ignore[attr-defined]
  adk_base_ss_mod.ListSessionsResponse = _StubListSessionsResponse  # type: ignore[attr-defined]

  adk_artifacts_mod = _ensure_pkg("google.adk.artifacts")
  adk_base_art_mod = _ensure_pkg("google.adk.artifacts.base_artifact_service")

  class _StubBaseArtifactService:
    pass

  class _StubArtifactVersion:

    def __init__(self, **kwargs: Any):
      self.__dict__.update(kwargs)

  adk_artifacts_mod.BaseArtifactService = _StubBaseArtifactService  # type: ignore[attr-defined]
  adk_base_art_mod.ArtifactVersion = _StubArtifactVersion  # type: ignore[attr-defined]

  adk_mem_mod = _ensure_pkg("google.adk.memory.base_memory_service")
  adk_mem_entry_mod = _ensure_pkg("google.adk.memory.memory_entry")
  adk_mem_mod.BaseMemoryService = object  # type: ignore[attr-defined]
  adk_mem_mod.SearchMemoryResponse = MagicMock  # type: ignore[attr-defined]
  adk_mem_entry_mod.MemoryEntry = MagicMock  # type: ignore[attr-defined]

  adk_agents_mod = _ensure_pkg("google.adk.agents")

  class _StubLlmAgent:

    def __init__(self, name: str = "test_agent", **kwargs: Any):
      self.name = name
      self.kwargs = kwargs

  class _StubRunner:

    def __init__(self, app_name: str, agent: Any, session_service: Any,
                 artifact_service: Any = None, memory_service: Any = None):
      self.app_name = app_name
      self.agent = agent
      self.session_service = session_service
      self.artifact_service = artifact_service
      self.memory_service = memory_service

    async def run_async(self, **kwargs: Any):
      del kwargs
      if False:  # pragma: no cover
        yield None

  adk_agents_mod.LlmAgent = _StubLlmAgent  # type: ignore[attr-defined]
  adk_mod.Runner = _StubRunner  # type: ignore[attr-defined]

  # a2a.*
  a2a_user_mod = _ensure_pkg("a2a.auth.user")

  class _StubUser(ABC):

    @property
    @abstractmethod
    def is_authenticated(self) -> bool:
      raise NotImplementedError

    @property
    @abstractmethod
    def user_name(self) -> str:
      raise NotImplementedError

  class _StubUnauthenticatedUser(_StubUser):

    @property
    def is_authenticated(self) -> bool:
      return False

    @property
    def user_name(self) -> str:
      return ""

  a2a_user_mod.User = _StubUser  # type: ignore[attr-defined]
  a2a_user_mod.UnauthenticatedUser = _StubUnauthenticatedUser  # type: ignore[attr-defined]

  a2a_ctx_mod = _ensure_pkg("a2a.server.context")

  class _StubServerCallContext:

    def __init__(self, user: Optional[_StubUser] = None,
                 state: Optional[dict[str, Any]] = None,
                 requested_extensions: Optional[set[str]] = None,
                 activated_extensions: Optional[set[str]] = None):
      self.user = user or _StubUnauthenticatedUser()
      self.state = state if state is not None else {}
      self.requested_extensions = set(requested_extensions or set())
      self.activated_extensions = set(activated_extensions or set())

  a2a_ctx_mod.ServerCallContext = _StubServerCallContext  # type: ignore[attr-defined]

  a2a_jsonrpc_mod = _ensure_pkg("a2a.server.apps.jsonrpc.jsonrpc_app")

  class _StubDefaultCallContextBuilder:

    def build(self, request: Any) -> _StubServerCallContext:
      return _StubServerCallContext(
          user=_StubUnauthenticatedUser(),
          state={"headers": dict(getattr(request, "headers", {}) or {})},
      )

  a2a_jsonrpc_mod.DefaultCallContextBuilder = _StubDefaultCallContextBuilder  # type: ignore[attr-defined]

  a2a_ts_mod = _ensure_pkg("a2a.server.tasks.task_store")

  class _StubTaskStore:
    pass

  a2a_ts_mod.TaskStore = _StubTaskStore  # type: ignore[attr-defined]

  a2a_tasks_mod = _ensure_pkg("a2a.server.tasks")

  class _StubTaskUpdater:

    def __init__(self, event_queue: Any, task_id: str, context_id: str):
      self.event_queue = event_queue
      self.task_id = task_id
      self.context_id = context_id
      self.submitted = False
      self.completed = False
      self.artifacts: list[Any] = []

    async def submit(self) -> None:
      self.submitted = True

    async def start_work(self) -> None:
      pass

    async def add_artifact(self, parts: list[Any], name: str = "") -> None:
      self.artifacts.append((name, parts))

    async def complete(self) -> None:
      self.completed = True

    async def update_status(self, *args: Any, **kwargs: Any) -> None:
      pass

  a2a_tasks_mod.TaskUpdater = _StubTaskUpdater  # type: ignore[attr-defined]

  a2a_exec_mod = _ensure_pkg("a2a.server.agent_execution")

  class _StubAgentExecutor:
    pass

  class _StubRequestContext:

    def __init__(self, message: Any = None, task_id: str = "task-1",
                 context_id: str = "ctx-1", call_context: Any = None,
                 user_input: str = "hello"):
      self.message = message
      self.task_id = task_id
      self.context_id = context_id
      self.call_context = call_context
      self.current_task = None
      self._user_input = user_input

    def get_user_input(self) -> str:
      return self._user_input

  a2a_exec_mod.AgentExecutor = _StubAgentExecutor  # type: ignore[attr-defined]
  a2a_exec_mod.RequestContext = _StubRequestContext  # type: ignore[attr-defined]

  a2a_events_mod = _ensure_pkg("a2a.server.events")
  a2a_events_mod.EventQueue = MagicMock  # type: ignore[attr-defined]

  a2a_types_mod = _ensure_pkg("a2a.types")

  class _StubTask:

    def __init__(self, id: str, context_id: str = "ctx-1",
                 status: Optional[dict[str, Any]] = None, **kwargs: Any):
      self.id = id
      self.context_id = context_id
      self.status = status or {"state": "completed"}
      self.extra = kwargs

    def model_dump(self, **kwargs: Any) -> dict[str, Any]:
      del kwargs
      return {
          "id": self.id,
          "context_id": self.context_id,
          "status": copy.deepcopy(self.status),
          **copy.deepcopy(self.extra),
      }

    @classmethod
    def model_validate(cls, data: dict[str, Any]) -> "_StubTask":
      if "_owner_id" in data:
        raise ValueError("_owner_id must not leak into Task payload")
      d = dict(data)
      return cls(id=d.pop("id"), context_id=d.pop("context_id", "ctx-1"),
                 status=d.pop("status", None), **d)

  class _StubInvalidRequestError:

    def __init__(self, message: str = ""):
      self.message = message

  class _StubTextPart:

    def __init__(self, text: str):
      self.text = text

  a2a_types_mod.Task = _StubTask  # type: ignore[attr-defined]
  a2a_types_mod.AgentCard = dict  # type: ignore[attr-defined]
  a2a_types_mod.AgentSkill = lambda **kw: kw  # type: ignore[attr-defined]
  a2a_types_mod.InvalidRequestError = _StubInvalidRequestError  # type: ignore[attr-defined]
  a2a_types_mod.Part = object  # type: ignore[attr-defined]
  a2a_types_mod.TaskState = py_types.SimpleNamespace(
      completed="completed", failed="failed")  # type: ignore[attr-defined]
  a2a_types_mod.TextPart = _StubTextPart  # type: ignore[attr-defined]
  a2a_types_mod.UnsupportedOperationError = Exception  # type: ignore[attr-defined]

  a2a_utils_mod = _ensure_pkg("a2a.utils")
  a2a_utils_mod.new_agent_text_message = lambda text: {
      "text": text
  }  # type: ignore[attr-defined]
  a2a_err_mod = _ensure_pkg("a2a.utils.errors")

  class _StubServerError(Exception):

    def __init__(self, error: Any = None):
      super().__init__(str(getattr(error, "message", error)))
      self.error = error

  a2a_err_mod.ServerError = _StubServerError  # type: ignore[attr-defined]

  # starlette & fastapi & vertexai
  starlette_req_mod = _ensure_pkg("starlette.requests")

  class _StubStarletteRequest:

    def __init__(self, headers: Optional[dict[str, str]] = None):
      self.headers = headers or {}

  starlette_req_mod.Request = _StubStarletteRequest  # type: ignore[attr-defined]

  fastapi_mod = _ensure_pkg("fastapi")

  class _StubFastAPI:

    def __init__(self, *args: Any, **kwargs: Any):
      del args, kwargs
      self.routes: list[Any] = []

    def add_api_route(self, path: str, endpoint: Any, methods: list[str]):
      self.routes.append(
          py_types.SimpleNamespace(path=path, endpoint=endpoint,
                                   methods=methods))

  fastapi_mod.FastAPI = _StubFastAPI  # type: ignore[attr-defined]
  fastapi_mod.Request = _StubStarletteRequest  # type: ignore[attr-defined]
  fastapi_mod.responses = py_types.SimpleNamespace(
      JSONResponse=lambda content: content)  # type: ignore[attr-defined]

  vertexai_mod = _ensure_pkg("vertexai")
  vertexai_mod.init = lambda **kw: None  # type: ignore[attr-defined]
  vertexai_mod.Client = lambda **kw: MagicMock()  # type: ignore[attr-defined]
  vertexai_mod.agent_engines = MagicMock()  # type: ignore[attr-defined]

  re_mod = _ensure_pkg("vertexai.preview.reasoning_engines")

  class _StubA2aAgent:

    def __init__(self, *, agent_card: Any, agent_executor_builder: Any = None,
                 task_store_builder: Any = None, **kwargs: Any):
      del kwargs
      self.agent_card = agent_card
      self._agent_executor_builder = agent_executor_builder
      self._task_store_builder = task_store_builder
      self.a2a_rest_adapter: Any = None
      self.agent_executor: Any = None
      self.task_store: Any = None

    def set_up(self) -> None:
      if self._agent_executor_builder:
        self.agent_executor = self._agent_executor_builder()
      if self._task_store_builder:
        self.task_store = self._task_store_builder()
      self.a2a_rest_adapter = py_types.SimpleNamespace(
          _context_builder=_StubDefaultCallContextBuilder())

  re_mod.A2aAgent = _StubA2aAgent  # type: ignore[attr-defined]
  re_a2a_tpl_mod = _ensure_pkg(
      "vertexai.preview.reasoning_engines.templates.a2a")
  re_a2a_tpl_mod.create_agent_card = lambda **kw: kw  # type: ignore[attr-defined]


def _load_file_module(module_name: str, file_path: Path) -> py_types.ModuleType:
  spec = importlib.util.spec_from_file_location(module_name, file_path)
  assert spec and spec.loader
  mod = importlib.util.module_from_spec(spec)
  sys.modules[module_name] = mod
  spec.loader.exec_module(mod)
  return mod


def _load_adk_a2a_package(
    monkeypatch: pytest.MonkeyPatch) -> tuple[py_types.ModuleType, ...]:
  _ensure_runtime_sdk_stubs(monkeypatch)
  monkeypatch.setenv("PROJECT_ID", "test-project")
  monkeypatch.setenv("REGION", "europe-west1")
  for key in list(sys.modules):
    if key == "src" or key.startswith(
        "src.") or key == "adk_a2a_agent_under_test":
      monkeypatch.delitem(sys.modules, key, raising=False)
  monkeypatch.syspath_prepend(str(ADK_A2A_DIR))
  auth_mod = importlib.import_module("src.auth")
  ss_mod = importlib.import_module("src.firestore_session_service")
  ts_mod = importlib.import_module("src.firestore_task_store")
  art_mod = importlib.import_module("src.firestore_artifact_service")
  agent_mod = _load_file_module("adk_a2a_agent_under_test",
                                ADK_A2A_DIR / "agent.py")
  return auth_mod, ss_mod, ts_mod, art_mod, agent_mod


@pytest.mark.parametrize(
    "service_path",
    [
        ADK_A2A_DIR / "src/firestore_session_service.py",
        ADK_DIR / "src/firestore_session_service.py",
    ],
    ids=["adk-a2a", "adk"],
)
def test_firestore_session_service_prevents_cross_user_and_cross_app_idor(
    monkeypatch: pytest.MonkeyPatch,
    service_path: Path,
) -> None:
  """Verifies cross-user and cross-app isolation for get, delete, create, and list."""
  _ensure_runtime_sdk_stubs(monkeypatch)
  mod = _load_file_module(f"session_svc_{service_path.parent.parent.name}",
                          service_path)
  fake_db = FakeFirestoreClient()
  monkeypatch.setattr(mod.firestore, "AsyncClient", lambda **kw: fake_db)
  svc = mod.FirestoreSessionService(project_id="test-project")

  async def _run() -> None:
    # Alice creates a session with sensitive state.
    alice_session = await svc.create_session(
        app_name="currency_agent",
        user_id="alice",
        session_id="ctx-aaaa-1111",
        state={"secret": "ALICE_PRIVATE_CONVERSATION_DATA"},
    )
    assert alice_session.id == "ctx-aaaa-1111"

    # 1. Cross-user get_session MUST return None.
    bob_read = await svc.get_session(
        app_name="currency_agent",
        user_id="bob",
        session_id="ctx-aaaa-1111",
    )
    assert bob_read is None

    # 2. Cross-app get_session MUST return None even for same user_id.
    other_app_read = await svc.get_session(
        app_name="other_app",
        user_id="alice",
        session_id="ctx-aaaa-1111",
    )
    assert other_app_read is None

    # 3. Cross-user delete_session MUST NOT delete Alice's session.
    await svc.delete_session(
        app_name="currency_agent",
        user_id="bob",
        session_id="ctx-aaaa-1111",
    )
    still_alice = await svc.get_session(
        app_name="currency_agent",
        user_id="alice",
        session_id="ctx-aaaa-1111",
    )
    assert still_alice is not None
    assert still_alice.state == {"secret": "ALICE_PRIVATE_CONVERSATION_DATA"}

    # 4. Bob creating a session with the SAME session_id MUST NOT overwrite Alice's.
    await svc.create_session(
        app_name="currency_agent",
        user_id="bob",
        session_id="ctx-aaaa-1111",
        state={"secret": "BOB_DATA"},
    )
    alice_after_bob_create = await svc.get_session(
        app_name="currency_agent",
        user_id="alice",
        session_id="ctx-aaaa-1111",
    )
    bob_own = await svc.get_session(
        app_name="currency_agent",
        user_id="bob",
        session_id="ctx-aaaa-1111",
    )
    assert alice_after_bob_create is not None
    assert alice_after_bob_create.state == {
        "secret": "ALICE_PRIVATE_CONVERSATION_DATA"
    }
    assert bob_own is not None
    assert bob_own.state == {"secret": "BOB_DATA"}

    # 5. list_sessions with empty user_id="" MUST raise ValueError (not leak all).
    with pytest.raises(ValueError, match="user_id"):
      await svc.list_sessions(app_name="currency_agent", user_id="")

    bob_list = await svc.list_sessions(app_name="currency_agent", user_id="bob")
    assert len(bob_list.sessions) == 1
    assert bob_list.sessions[0].user_id == "bob"

    all_list = await svc.list_sessions(app_name="currency_agent", user_id=None)
    assert len(all_list.sessions) == 2

    # 6. Defense-in-depth: even if a document at Bob's key has mismatched owner,
    # get_session and delete_session reject it.
    tampered_doc_id = mod._build_session_doc_id("currency_agent", "mallory",
                                                "tampered-sid")
    fake_db.collections["adk_sessions"][tampered_doc_id] = {
        "id": "tampered-sid",
        "app_name": "currency_agent",
        "user_id": "alice",
        "state": {
            "secret": "ALICE"
        },
        "last_update_time": 1.0,
    }
    assert await svc.get_session(app_name="currency_agent", user_id="mallory",
                                 session_id="tampered-sid") is None
    await svc.delete_session(app_name="currency_agent", user_id="mallory",
                             session_id="tampered-sid")
    assert tampered_doc_id in fake_db.collections["adk_sessions"]

    # 7. Slash/colon/long principals work safely without path traversal.
    slash_user = "https://accounts.google.com/1122334455:sub"
    long_sid = "s" * 600
    s_special = await svc.create_session(
        app_name="app/v1:prod",
        user_id=slash_user,
        session_id=long_sid,
        state={"ok": True},
    )
    loaded_special = await svc.get_session(
        app_name="app/v1:prod",
        user_id=slash_user,
        session_id=s_special.id,
    )
    assert loaded_special is not None
    assert loaded_special.state == {"ok": True}

  asyncio.run(_run())


def test_firestore_task_store_enforces_authenticated_owner_isolation(
    monkeypatch: pytest.MonkeyPatch,) -> None:
  auth_mod, _, ts_mod, _, _ = _load_adk_a2a_package(monkeypatch)
  from a2a.server.context import ServerCallContext
  from a2a.types import Task, TaskState

  fake_db = FakeFirestoreClient()
  monkeypatch.setattr(ts_mod.firestore, "AsyncClient", lambda **kw: fake_db)
  store = ts_mod.FirestoreTaskStore(project_id="test-project")

  alice_ctx = ServerCallContext(user=auth_mod.AuthenticatedUser("alice"))
  bob_ctx = ServerCallContext(user=auth_mod.AuthenticatedUser("bob"))
  unauth_ctx = ServerCallContext()

  def _make_task(task_id: str, context_id: str) -> Any:
    try:
      from a2a.types import TaskStatus
      return Task(id=task_id, context_id=context_id,
                  status=TaskStatus(state=TaskState.completed))
    except ImportError:
      return Task(id=task_id, context_id=context_id)

  async def _run() -> None:
    alice_task = _make_task("task-123", "ctx-alice")

    # Unauthenticated save MUST fail closed.
    with pytest.raises(PermissionError):
      await store.save(alice_task, None)
    with pytest.raises(PermissionError):
      await store.save(alice_task, unauth_ctx)

    # Alice saves task-123.
    await store.save(alice_task, alice_ctx)
    loaded_by_alice = await store.get("task-123", alice_ctx)
    assert loaded_by_alice is not None
    assert loaded_by_alice.id == "task-123"

    # Bob and unauthenticated callers CANNOT read or delete Alice's task.
    assert await store.get("task-123", bob_ctx) is None
    assert await store.get("task-123", unauth_ctx) is None
    assert await store.get("task-123", None) is None

    await store.delete("task-123", bob_ctx)
    await store.delete("task-123", unauth_ctx)
    await store.delete("task-123", None)
    assert await store.get("task-123", alice_ctx) is not None

    # Alice can delete her own task.
    await store.delete("task-123", alice_ctx)
    assert await store.get("task-123", alice_ctx) is None

  asyncio.run(_run())


def test_a2a_executor_binds_authenticated_principal_and_ignores_metadata_user_id(
    monkeypatch: pytest.MonkeyPatch,) -> None:
  auth_mod, ss_mod, _, _, agent_mod = _load_adk_a2a_package(monkeypatch)
  from a2a.server.context import ServerCallContext
  from a2a.utils.errors import ServerError
  from google.adk.events import Event
  from google.genai import types

  fake_db = FakeFirestoreClient()
  monkeypatch.setattr(ss_mod.firestore, "AsyncClient", lambda **kw: fake_db)
  session_svc = ss_mod.FirestoreSessionService(project_id="test-project")

  executor = agent_mod.CurrencyAgentExecutorWithRunner(
      agent=agent_mod.llm_agent)
  executor._init_adk()
  executor.runner.session_service = session_svc

  recorded_run_user_ids: list[str] = []

  async def _fake_run_async(*, session_id: str, user_id: str, new_message: Any):
    del session_id, new_message
    recorded_run_user_ids.append(user_id)
    ev = MagicMock(spec=Event)
    ev.is_final_response.return_value = True
    ev.content = types.Content(role="model",
                               parts=[types.Part(text="1 USD = 10.5 SEK")])
    yield ev

  executor.runner.run_async = _fake_run_async

  async def _run() -> None:
    # Seed Alice's private session under context_id="shared-ctx".
    await session_svc.create_session(
        app_name=executor.runner.app_name,
        user_id="alice",
        session_id="shared-ctx",
        state={"secret": "ALICE_ONLY"},
    )

    # 1. Unauthenticated request MUST be rejected before creating tasks/sessions.
    unauth_req = MagicMock()
    unauth_req.message = py_types.SimpleNamespace(metadata={"user_id": "alice"})
    unauth_req.call_context = ServerCallContext()
    unauth_req.task_id = "task-unauth"
    unauth_req.context_id = "shared-ctx"

    with pytest.raises(ServerError):
      await executor.execute(unauth_req, MagicMock())
    assert recorded_run_user_ids == []

    # 2. Authenticated caller "bob" attempts to spoof metadata={'user_id': 'alice'}
    # and reuse Alice's context_id="shared-ctx".
    bob_req = MagicMock()
    bob_req.message = py_types.SimpleNamespace(metadata={"user_id": "alice"})
    bob_req.call_context = ServerCallContext(
        user=auth_mod.AuthenticatedUser("bob"))
    bob_req.task_id = "task-bob"
    bob_req.context_id = "shared-ctx"
    bob_req.current_task = None
    bob_req.get_user_input.return_value = "USD to SEK?"

    with patch.object(agent_mod, "TaskUpdater") as mock_updater_cls:
      updater_inst = MagicMock()

      async def _noop(*args: Any, **kwargs: Any) -> None:
        del args, kwargs

      updater_inst.submit = _noop
      updater_inst.start_work = _noop
      updater_inst.add_artifact = _noop
      updater_inst.complete = _noop
      updater_inst.update_status = _noop
      mock_updater_cls.return_value = updater_inst

      await executor.execute(bob_req, MagicMock())

    # Executor MUST have run strictly as "bob", never "alice", and Alice's
    # session state MUST remain untouched.
    assert recorded_run_user_ids == ["bob"]
    alice_sess = await session_svc.get_session(
        app_name=executor.runner.app_name,
        user_id="alice",
        session_id="shared-ctx",
    )
    bob_sess = await session_svc.get_session(
        app_name=executor.runner.app_name,
        user_id="bob",
        session_id="shared-ctx",
    )
    assert alice_sess is not None and alice_sess.state == {
        "secret": "ALICE_ONLY"
    }
    assert bob_sess is not None and bob_sess.state == {}

  asyncio.run(_run())


def test_authenticated_call_context_builder_verifies_tokens(
    monkeypatch: pytest.MonkeyPatch,) -> None:
  auth_mod, _, _, art_mod, agent_mod = _load_adk_a2a_package(monkeypatch)
  from starlette.requests import Request

  # WellKnownCardA2aAgent wires AuthenticatedCallContextBuilder on set_up().
  assert isinstance(agent_mod.agent.a2a_rest_adapter._context_builder,
                    auth_mod.AuthenticatedCallContextBuilder)

  builder = auth_mod.AuthenticatedCallContextBuilder()

  class _FakeHeaders(dict):

    def getlist(self, key: str) -> list[str]:
      val = self.get(key)
      return [val] if val is not None else []

  class _FakeRequest:

    def __init__(self, headers: dict[str, str]):
      self.headers = _FakeHeaders(headers)

  # 1. Valid OIDC JWT Bearer token -> AuthenticatedUser(sub)
  with patch.object(auth_mod.id_token, "verify_oauth2_token", return_value={
      "sub": "google-sub-alice",
      "exp": 9999999999
  }):
    req = _FakeRequest({"Authorization": "Bearer header.payload.sig_alice"})
    ctx = builder.build(req)  # type: ignore[arg-type]
    assert ctx.user.is_authenticated is True
    assert ctx.user.user_name == "google-sub-alice"

  # 2. Forged/invalid JWT signature -> remains unauthenticated
  with patch.object(auth_mod.id_token, "verify_oauth2_token",
                    side_effect=ValueError("Invalid signature")):
    req_bad = _FakeRequest({"Authorization": "Bearer forged.jwt.token"})
    ctx_bad = builder.build(req_bad)  # type: ignore[arg-type]
    assert ctx_bad.user.is_authenticated is False
    with pytest.raises(PermissionError):
      auth_mod.require_authenticated_user(ctx_bad)

  # 3. Opaque OAuth2 access token -> verified via POST body (never query string)
  mock_resp = MagicMock()
  mock_resp.status_code = 200
  mock_resp.json.return_value = {"sub": "oauth-sub-bob", "exp": "9999999999"}
  with patch.object(auth_mod.requests, "post",
                    return_value=mock_resp) as mock_post:
    principal = auth_mod.authenticate_headers(
        {"Authorization": "Bearer opaque_test_access_token"})
    assert principal == "oauth-sub-bob"
    mock_post.assert_called_once()
    assert mock_post.call_args.kwargs["data"] == {
        "access_token": "opaque_test_access_token"
    }

  # 4. Artifact key builder prevents delimiter collisions and slash injection.
  fake_art_db = FakeFirestoreClient()
  monkeypatch.setattr(art_mod.firestore, "AsyncClient",
                      lambda **kw: fake_art_db)
  art_svc = art_mod.FirestoreArtifactService(project_id="test-project")
  ref1 = art_svc._get_doc_ref("a_b", "c", "s", "file.txt")
  ref2 = art_svc._get_doc_ref("a", "b_c", "s", "file.txt")
  ref_none = art_svc._get_doc_ref("a", "https://issuer/u1", None, "dir/f.txt")
  ref_lit = art_svc._get_doc_ref("a", "https://issuer/u1", "user_scoped",
                                 "dir/f.txt")
  assert ref1.id != ref2.id
  assert ref_none.id != ref_lit.id
  assert "/" not in ref_none.id
