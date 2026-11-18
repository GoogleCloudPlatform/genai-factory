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

import ast
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

import httpx
import pytest

import server
from src.domain_guardrail import (
    create_workspace_domain_before_tool_callback,
    parse_allowed_domains,
    validate_recipient_domains,
)

ALLOWED = ("example.com", "corp.example.com")


def _fake_ctx(bearer: str = "test-bearer-token") -> MagicMock:
  ctx = MagicMock()
  ctx.request_context.request.headers = {
      "Authorization": f"Bearer {bearer}",
      "X-Serverless-Authorization": "Bearer id-token",
  }
  return ctx


def test_parse_allowed_domains_normalizes_inputs() -> None:
  parsed = parse_allowed_domains(" @Example.COM., corp.example.com , invalid ")
  assert parsed == frozenset({"example.com", "corp.example.com"})


@pytest.mark.parametrize(
    "recipients,expected",
    [
        ("alice@example.com", ["alice@example.com"]),
        (
            ["Alice Smith <ALICE@Example.com>", "bob@corp.example.com"],
            ["ALICE@example.com", "bob@corp.example.com"],
        ),
        (
            "alice@example.com, team@corp.example.com",
            ["alice@example.com", "team@corp.example.com"],
        ),
    ],
)
def test_validate_recipient_domains_allows_internal(
    recipients: str | list[str],
    expected: list[str],
) -> None:
  addrs, err = validate_recipient_domains(
      recipients,
      ALLOWED,
      field_name="to",
      require_at_least_one=True,
  )
  assert err is None
  assert addrs == expected


@pytest.mark.parametrize(
    "recipients",
    [
        "",
        [],
        "attacker@gmail.com",
        ["alice@example.com", "exfil@external.org"],
        "alice@sub.example.com",
        "alice@notexample.com",
        '"alice@example.com" <attacker@evil.com>',
        '"attacker@evil.com" <alice@example.com>',
        "alice@example.com, hidden@evil.com",
        "alice@example.com\r\nBcc: leak@evil.com",
        "not-an-email",
        "alice@@example.com",
    ],
)
def test_validate_recipient_domains_blocks_external_and_spoofed(
    recipients: str | list[str],) -> None:
  addrs, err = validate_recipient_domains(
      recipients,
      ALLOWED,
      field_name="to",
      require_at_least_one=True,
  )
  assert addrs == []
  assert err is not None


def test_validate_recipient_domains_calendar_allows_empty_attendees() -> None:
  addrs, err = validate_recipient_domains(
      None,
      ALLOWED,
      field_name="attendees",
      require_at_least_one=False,
  )
  assert err is None
  assert addrs == []


def test_validate_recipient_domains_enforces_self_only() -> None:
  ok_addrs, ok_err = validate_recipient_domains(
      "alice@example.com",
      ALLOWED,
      caller_email="alice@example.com",
      self_only=True,
      require_at_least_one=True,
  )
  assert ok_err is None
  assert ok_addrs == ["alice@example.com"]

  blocked_addrs, blocked_err = validate_recipient_domains(
      "colleague@example.com",
      ALLOWED,
      caller_email="alice@example.com",
      self_only=True,
      require_at_least_one=True,
  )
  assert blocked_addrs == []
  assert blocked_err is not None


def test_adk_before_tool_callback_blocks_external_and_allows_internal() -> None:
  callback = create_workspace_domain_before_tool_callback(["example.com"])
  email_tool = SimpleNamespace(name="send_message")
  calendar_tool = SimpleNamespace(name="create_event")
  search_tool = SimpleNamespace(name="search_messages")

  # Read-only tool is untouched.
  assert callback(search_tool, {"query": "from:external.com"}, None) is None

  # External BCC is deterministically blocked before execution.
  blocked = callback(
      email_tool,
      {
          "to": ["alice@example.com"],
          "bcc": ["leak@gmail.com"],
          "subject": "Report",
      },
      None,
  )
  assert blocked is not None and blocked["status"] == "ERROR"

  # Empty recipient list on email tool is blocked.
  empty = callback(email_tool, {"subject": "No recipients"}, None)
  assert empty is not None and empty["status"] == "ERROR"

  # Internal-only email passes through to tool execution.
  allowed = callback(
      email_tool,
      {
          "to": ["alice@example.com"],
          "cc": ["bob@example.com"],
          "subject": "Internal sync",
      },
      None,
  )
  assert allowed is None

  # Calendar event with external attendee is blocked; empty attendees allowed.
  cal_blocked = callback(
      calendar_tool,
      {
          "summary": "Review",
          "attendees": ["guest@external.io"]
      },
      None,
  )
  assert cal_blocked is not None and cal_blocked["status"] == "ERROR"
  assert callback(calendar_tool, {"summary": "Focus block"}, None) is None


@pytest.mark.asyncio
async def test_mcp_server_hard_blocks_external_without_http_call(
    monkeypatch: pytest.MonkeyPatch,) -> None:
  monkeypatch.setattr(server, "ALLOWED_DOMAINS", frozenset({"example.com"}))
  called = False

  async def _forbid_post(*args: object, **kwargs: object) -> httpx.Response:
    nonlocal called
    called = True
    raise AssertionError("External recipient must never reach Workspace API")

  monkeypatch.setattr(httpx.AsyncClient, "post", _forbid_post)

  result = json.loads(await server.send_internal_email(
      _fake_ctx(),
      to=["alice@example.com"],
      cc=["exfil@gmail.com"],
      subject="Prompt injection test",
      body="Sensitive payload",
  ))
  assert result["status"] == "BLOCKED"
  assert not called


@pytest.mark.asyncio
async def test_mcp_server_sends_when_all_recipients_internal(
    monkeypatch: pytest.MonkeyPatch,) -> None:
  monkeypatch.setattr(server, "ALLOWED_DOMAINS", frozenset({"example.com"}))
  captured: dict[str, object] = {}

  async def _record_post(
      self: httpx.AsyncClient,
      url: str,
      **kwargs: object,
  ) -> httpx.Response:
    del self
    captured["url"] = url
    captured["headers"] = kwargs.get("headers")
    return httpx.Response(200, json={"id": "msg-123"})

  monkeypatch.setattr(httpx.AsyncClient, "post", _record_post)

  result = json.loads(await server.send_internal_email(
      _fake_ctx("delegated-user-oauth-token"),
      to=["alice@example.com"],
      subject="Internal status",
      body="Approved internal update",
  ))
  assert result == {
      "status": "SENT",
      "id": "msg-123",
      "recipients": ["alice@example.com"],
  }
  assert str(captured["url"]).endswith("/users/me/messages/send")


def test_production_modules_contain_no_mock_fallbacks() -> None:
  app_root = Path(__file__).resolve().parents[1]
  forbidden_tokens = {"MagicMock", "unittest.mock", "mock_success", "fake_send"}
  for rel in ("server.py", "src/domain_guardrail.py"):
    source = (app_root / rel).read_text(encoding="utf-8")
    tree = ast.parse(source, filename=rel)
    assert tree is not None
    for token in forbidden_tokens:
      assert token not in source, f"Forbidden token {token} found in {rel}"
