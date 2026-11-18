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
"""Cloud Run Streamable HTTP MCP proxy enforcing internal Workspace domains."""

import base64
from email.message import EmailMessage
import json
import logging
import os
from typing import Any

from fastmcp import Context, FastMCP
import httpx

from src.domain_guardrail import (
    parse_allowed_domains,
    validate_recipient_domains,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("workspace-mcp-proxy")

ALLOWED_DOMAINS = parse_allowed_domains(
    os.environ.get("ALLOWED_RECIPIENT_DOMAINS", ""))
ENABLE_AUTOMATED_INTERNAL_SEND_TOOL = (os.environ.get(
    "ENABLE_AUTOMATED_INTERNAL_SEND_TOOL", "false").lower() == "true")
AUTOMATED_SEND_SELF_ONLY = (os.environ.get("AUTOMATED_SEND_SELF_ONLY",
                                           "true").lower() == "true")
GMAIL_API_BASE = os.environ.get("GMAIL_API_BASE",
                                "https://gmail.googleapis.com/gmail/v1")
CALENDAR_API_BASE = os.environ.get("CALENDAR_API_BASE",
                                   "https://www.googleapis.com/calendar/v3")

mcp = FastMCP("Google Workspace Internal Domain Guardrail")


def _extract_user_bearer_token(ctx: Context) -> str | None:
  """Extracts the delegated OAuth 2.0 access token forwarded by Gemini Enterprise.

  When Gemini Enterprise invokes a private Cloud Run MCP server, Cloud Run IAM
  authentication uses X-Serverless-Authorization while the user's OAuth 2.0
  token is preserved in Authorization (or X-GCP-Access-Token).
  """
  if not ctx.request_context or not ctx.request_context.request:
    return None
  headers = ctx.request_context.request.headers
  explicit_token = headers.get("X-GCP-Access-Token")
  if explicit_token and explicit_token.strip():
    return explicit_token.strip()
  auth_header = headers.get("Authorization", "")
  if auth_header.startswith("Bearer "):
    token = auth_header.removeprefix("Bearer ").strip()
    if token:
      return token
  return None


def _sanitize_header_line(value: str,
                          field_name: str) -> tuple[str, str | None]:
  if "\r" in value or "\n" in value or "\x00" in value:
    return "", f"Control or newline characters are not allowed in '{field_name}'."
  return value.strip(), None


def _build_raw_mime_message(
    to_addrs: list[str],
    cc_addrs: list[str],
    bcc_addrs: list[str],
    subject: str,
    body: str,
) -> str:
  msg = EmailMessage()
  msg["To"] = ", ".join(to_addrs)
  if cc_addrs:
    msg["Cc"] = ", ".join(cc_addrs)
  if bcc_addrs:
    msg["Bcc"] = ", ".join(bcc_addrs)
  msg["Subject"] = subject
  msg.set_content(body)
  return base64.urlsafe_b64encode(msg.as_bytes()).decode("ascii")


async def _fetch_authenticated_gmail_address(
    client: httpx.AsyncClient,
    bearer_token: str,
) -> tuple[str | None, str | None]:
  resp = await client.get(
      f"{GMAIL_API_BASE}/users/me/profile",
      headers={"Authorization": f"Bearer {bearer_token}"},
  )
  if resp.status_code != 200:
    return None, (
        f"Failed to verify caller Gmail profile (HTTP {resp.status_code}).")
  email_address = resp.json().get("emailAddress")
  if not email_address:
    return None, "Gmail profile response did not contain emailAddress."
  return str(email_address), None


async def _validate_and_send_gmail(
    ctx: Context,
    *,
    to: list[str] | str,
    subject: str,
    body: str,
    cc: list[str] | str | None = None,
    bcc: list[str] | str | None = None,
    draft_only: bool = False,
    self_only: bool = False,
    prepend_automated_banner: bool = False,
) -> str:
  bearer_token = _extract_user_bearer_token(ctx)
  if not bearer_token:
    return json.dumps({
        "status": "ERROR",
        "error": "Missing delegated OAuth 2.0 Bearer token in request headers.",
    })

  clean_subject, subj_err = _sanitize_header_line(subject, "subject")
  if subj_err:
    return json.dumps({"status": "ERROR", "error": subj_err})

  async with httpx.AsyncClient(timeout=15.0) as client:
    caller_email: str | None = None
    if self_only:
      caller_email, prof_err = await _fetch_authenticated_gmail_address(
          client, bearer_token)
      if prof_err:
        return json.dumps({"status": "ERROR", "error": prof_err})

    to_addrs, to_err = validate_recipient_domains(
        to,
        ALLOWED_DOMAINS,
        field_name="to",
        require_at_least_one=not draft_only,
        caller_email=caller_email,
        self_only=self_only,
    )
    if to_err:
      logger.warning("Blocked Gmail %s on 'to': %s",
                     "draft" if draft_only else "send", to_err)
      return json.dumps({"status": "BLOCKED", "error": to_err})

    cc_addrs, cc_err = validate_recipient_domains(
        cc,
        ALLOWED_DOMAINS,
        field_name="cc",
        require_at_least_one=False,
        caller_email=caller_email,
        self_only=self_only,
    )
    if cc_err:
      logger.warning("Blocked Gmail %s on 'cc': %s",
                     "draft" if draft_only else "send", cc_err)
      return json.dumps({"status": "BLOCKED", "error": cc_err})

    bcc_addrs, bcc_err = validate_recipient_domains(
        bcc,
        ALLOWED_DOMAINS,
        field_name="bcc",
        require_at_least_one=False,
        caller_email=caller_email,
        self_only=self_only,
    )
    if bcc_err:
      logger.warning("Blocked Gmail %s on 'bcc': %s",
                     "draft" if draft_only else "send", bcc_err)
      return json.dumps({"status": "BLOCKED", "error": bcc_err})

    if not draft_only and not (to_addrs or cc_addrs or bcc_addrs):
      return json.dumps({
          "status": "BLOCKED",
          "error": "At least one internal recipient is required.",
      })

    effective_body = ("[Automated AI Agent Notification]\n\n" +
                      body if prepend_automated_banner else body)
    raw_mime = _build_raw_mime_message(
        to_addrs,
        cc_addrs,
        bcc_addrs,
        clean_subject,
        effective_body,
    )
    if draft_only:
      url = f"{GMAIL_API_BASE}/users/me/drafts"
      payload: dict[str, Any] = {"message": {"raw": raw_mime}}
    else:
      url = f"{GMAIL_API_BASE}/users/me/messages/send"
      payload = {"raw": raw_mime}

    resp = await client.post(
        url,
        headers={"Authorization": f"Bearer {bearer_token}"},
        json=payload,
    )
    if resp.status_code not in (200, 201):
      return json.dumps({
          "status": "ERROR",
          "http_status": resp.status_code,
          "error": resp.text,
      })
    data = resp.json()
    return json.dumps({
        "status": "DRAFT_CREATED" if draft_only else "SENT",
        "id": data.get("id"),
        "recipients": to_addrs + cc_addrs + bcc_addrs,
    })


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    })
async def send_internal_email(
    ctx: Context,
    to: list[str] | str,
    subject: str,
    body: str,
    cc: list[str] | str | None = None,
    bcc: list[str] | str | None = None,
) -> str:
  """Sends an email strictly to allowlisted internal domains after HITL approval.

  Gemini Enterprise prompts the user for Human-in-the-Loop confirmation because
  readOnlyHint is False, and this proxy deterministically rejects any recipient
  outside ALLOWED_RECIPIENT_DOMAINS across to, cc, and bcc.
  """
  return await _validate_and_send_gmail(
      ctx,
      to=to,
      subject=subject,
      body=body,
      cc=cc,
      bcc=bcc,
      draft_only=False,
      self_only=False,
  )


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    })
async def create_email_draft(
    ctx: Context,
    subject: str,
    body: str,
    to: list[str] | str | None = None,
    cc: list[str] | str | None = None,
    bcc: list[str] | str | None = None,
) -> str:
  """Creates a Gmail draft while blocking non-allowlisted external recipients."""
  return await _validate_and_send_gmail(
      ctx,
      to=to or [],
      subject=subject,
      body=body,
      cc=cc,
      bcc=bcc,
      draft_only=True,
      self_only=False,
  )


@mcp.tool(
    annotations={
        "readOnlyHint": False,
        "destructiveHint": True,
        "idempotentHint": False,
        "openWorldHint": False,
    })
async def create_internal_calendar_event(
    ctx: Context,
    summary: str,
    start_time: str,
    end_time: str,
    attendees: list[str] | str | None = None,
    description: str | None = None,
) -> str:
  """Creates a primary Google Calendar event restricted to internal attendees.

  Allows personal events without attendees or invites scoped exclusively to
  ALLOWED_RECIPIENT_DOMAINS, rejecting any external attendee domain.
  """
  bearer_token = _extract_user_bearer_token(ctx)
  if not bearer_token:
    return json.dumps({
        "status": "ERROR",
        "error": "Missing delegated OAuth 2.0 Bearer token in request headers.",
    })

  clean_summary, sum_err = _sanitize_header_line(summary, "summary")
  if sum_err:
    return json.dumps({"status": "ERROR", "error": sum_err})

  attendee_addrs, att_err = validate_recipient_domains(
      attendees,
      ALLOWED_DOMAINS,
      field_name="attendees",
      require_at_least_one=False,
  )
  if att_err:
    logger.warning("Blocked Calendar invite on 'attendees': %s", att_err)
    return json.dumps({"status": "BLOCKED", "error": att_err})

  event_body: dict[str, Any] = {
      "summary": clean_summary,
      "start": {
          "dateTime": start_time
      },
      "end": {
          "dateTime": end_time
      },
  }
  if description:
    event_body["description"] = description
  if attendee_addrs:
    event_body["attendees"] = [{"email": email} for email in attendee_addrs]

  async with httpx.AsyncClient(timeout=15.0) as client:
    resp = await client.post(
        f"{CALENDAR_API_BASE}/calendars/primary/events",
        params={"sendUpdates": "all"},
        headers={"Authorization": f"Bearer {bearer_token}"},
        json=event_body,
    )
    if resp.status_code not in (200, 201):
      return json.dumps({
          "status": "ERROR",
          "http_status": resp.status_code,
          "error": resp.text,
      })
    data = resp.json()
    return json.dumps({
        "status": "EVENT_CREATED",
        "id": data.get("id"),
        "htmlLink": data.get("htmlLink"),
        "attendees": attendee_addrs,
    })


if ENABLE_AUTOMATED_INTERNAL_SEND_TOOL:

  @mcp.tool(
      annotations={
          "readOnlyHint": True,
          "destructiveHint": False,
          "idempotentHint": False,
          "openWorldHint": False,
      })
  async def send_automated_internal_email(
      ctx: Context,
      to: list[str] | str,
      subject: str,
      body: str,
  ) -> str:
    """Sends unattended internal notifications while hard-blocking external domains.

    Exposed only when ENABLE_AUTOMATED_INTERNAL_SEND_TOOL=true. Sets
    readOnlyHint=True so Scheduled Chat Agent runs can execute without pausing,
    while deterministically enforcing ALLOWED_RECIPIENT_DOMAINS (and restricting
    to the caller's own email when AUTOMATED_SEND_SELF_ONLY=true).
    """
    return await _validate_and_send_gmail(
        ctx,
        to=to,
        subject=subject,
        body=body,
        draft_only=False,
        self_only=AUTOMATED_SEND_SELF_ONLY,
        prepend_automated_banner=True,
    )


if __name__ == "__main__":
  port = int(os.environ.get("PORT", "8080"))
  logger.info(
      "Starting Workspace MCP Proxy on port %d (allowed_domains=%s, "
      "automated_send_tool=%s, automated_self_only=%s)",
      port,
      sorted(ALLOWED_DOMAINS),
      ENABLE_AUTOMATED_INTERNAL_SEND_TOOL,
      AUTOMATED_SEND_SELF_ONLY,
  )
  mcp.run(transport="streamable-http", host="0.0.0.0", port=port, path="/mcp")
