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
"""Deterministic RFC-5322 recipient-domain allowlist for MCP and ADK tools."""

from collections.abc import Callable, Iterable, Sequence
from email.utils import getaddresses
import logging
import re
from typing import Any

logger = logging.getLogger(__name__)

_DOMAIN_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
                             r"(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$")
_EMAIL_ADDRESS_FIELDS = (
    "to",
    "cc",
    "bcc",
    "recipients",
    "to_recipients",
    "cc_recipients",
    "bcc_recipients",
)
_CALENDAR_ATTENDEE_FIELDS = (
    "attendees",
    "attendee_emails",
)
_DEFAULT_MUTATIVE_TOOLS = frozenset({
    "send_message",
    "send_mail",
    "send_email",
    "send_internal_email",
    "send_automated_internal_email",
    "reply",
    "forward",
    "create_draft",
    "create_email_draft",
    "create_event",
    "create_calendar_event",
    "create_internal_calendar_event",
})


def parse_allowed_domains(
    raw_domains: str | Iterable[str] | None,) -> frozenset[str]:
  """Normalizes a comma-separated string or iterable of allowed domains."""
  if raw_domains is None:
    return frozenset()
  items = (raw_domains.split(",")
           if isinstance(raw_domains, str) else raw_domains)
  normalized: set[str] = set()
  for item in items:
    cleaned = item.strip().lstrip("@").rstrip(".").lower()
    if cleaned and _DOMAIN_PATTERN.match(cleaned):
      normalized.add(cleaned)
  return frozenset(normalized)


def _validate_single_addr_spec(
    display_name: str,
    addr_spec: str,
    allowed_domains: frozenset[str],
    field_name: str,
) -> tuple[str | None, str | None]:
  """Validates one parsed (display_name, addr_spec) tuple."""
  if not addr_spec or any(ch in addr_spec for ch in (" ", "\t", "<", ">", ",")):
    return None, f"Malformed recipient address in '{field_name}'."

  if addr_spec.count("@") != 1:
    return None, f"Invalid email format '{addr_spec}' in '{field_name}'."

  local_part, domain_part = addr_spec.split("@", 1)
  domain = domain_part.strip().rstrip(".").lower()
  if not local_part or not domain or not _DOMAIN_PATTERN.match(domain):
    return None, f"Invalid recipient domain in '{field_name}': '{addr_spec}'."

  if domain not in allowed_domains:
    allowed_str = ", ".join(sorted(allowed_domains))
    return None, (
        f"Recipient '{addr_spec}' in '{field_name}' is outside allowed "
        f"internal domains ({allowed_str}). External egress is blocked.")

  # Defense-in-depth against display-name spoofing such as
  # '"attacker@external.com" <colleague@example.com>'.
  if "@" in display_name:
    for _, embedded_addr in getaddresses([display_name]):
      if "@" in embedded_addr:
        embedded_domain = embedded_addr.rsplit("@", 1)[-1].rstrip(".").lower()
        if embedded_domain not in allowed_domains:
          return None, (
              f"Display name in '{field_name}' embeds disallowed external "
              f"address '{embedded_addr}'.")

  return f"{local_part}@{domain}", None


def validate_recipient_domains(
    recipients: str | Sequence[str] | None,
    allowed_domains: Iterable[str],
    *,
    field_name: str = "to",
    require_at_least_one: bool = False,
    caller_email: str | None = None,
    self_only: bool = False,
) -> tuple[list[str], str | None]:
  """Parses and validates RFC-5322 recipient lists against allowed_domains.

  Args:
    recipients: Comma-separated recipient string or sequence of strings.
    allowed_domains: Allowed internal email domains (e.g. ['example.com']).
    field_name: Field label included in rejection messages.
    require_at_least_one: Reject when no recipient addresses are present.
    caller_email: Authenticated user email when enforcing self_only=True.
    self_only: Restrict recipients strictly to caller_email.

  Returns:
    Tuple of (normalized_addresses, error_message). error_message is None when
    all recipients pass validation; otherwise normalized_addresses is empty.
  """
  normalized_allowed = parse_allowed_domains(allowed_domains)
  if not normalized_allowed:
    return [], (
        "ALLOWED_RECIPIENT_DOMAINS is empty; failing closed on outbound "
        "Workspace action.")

  if recipients is None:
    raw_items: list[str] = []
  elif isinstance(recipients, str):
    raw_items = [recipients] if recipients.strip() else []
  elif isinstance(recipients, Sequence):
    raw_items = [str(item) for item in recipients if str(item).strip()]
  else:
    return [], f"Unsupported recipient type for '{field_name}'."

  for raw in raw_items:
    if "\r" in raw or "\n" in raw or "\x00" in raw:
      return [], (
          f"Control or newline characters are not permitted in '{field_name}'.")

  if not raw_items:
    if require_at_least_one:
      return [], f"At least one internal recipient is required in '{field_name}'."
    return [], None

  parsed_pairs = getaddresses(raw_items)
  if not parsed_pairs:
    return [], f"Unable to parse recipient addresses in '{field_name}'."

  validated: list[str] = []
  for display_name, addr_spec in parsed_pairs:
    normalized_addr, err = _validate_single_addr_spec(
        display_name,
        addr_spec,
        normalized_allowed,
        field_name,
    )
    if err is not None or normalized_addr is None:
      return [], err or f"Invalid recipient in '{field_name}'."

    if self_only:
      if not caller_email or normalized_addr.lower() != caller_email.lower():
        return [], (
            f"Automated send restricts '{field_name}' to the authenticated "
            f"caller address; rejected '{normalized_addr}'.")

    validated.append(normalized_addr)

  if require_at_least_one and not validated:
    return [], f"At least one internal recipient is required in '{field_name}'."

  return validated, None


def create_workspace_domain_before_tool_callback(
    allowed_domains: Iterable[str],
    *,
    mutative_tools: Iterable[str] | None = None,
) -> Callable[[Any, dict[str, Any], Any], dict[str, Any] | None]:
  """Builds an ADK before_tool_callback enforcing internal recipient domains.

  Attach the returned callable to an ADK LlmAgent's `before_tool_callback` on
  Vertex AI Agent Engine or Cloud Run to deterministically block external
  email or calendar recipients before tool execution.
  """
  normalized_allowed = parse_allowed_domains(allowed_domains)
  watched_tools = (frozenset(mutative_tools)
                   if mutative_tools is not None else _DEFAULT_MUTATIVE_TOOLS)

  def _before_tool_callback(
      tool: Any,
      args: dict[str, Any],
      tool_context: Any,
  ) -> dict[str, Any] | None:
    del tool_context
    tool_name = getattr(tool, "name", "")
    if tool_name not in watched_tools:
      return None

    is_calendar = "calendar" in tool_name or tool_name.endswith("event")
    seen_email_recipient = False

    for key, value in args.items():
      lowered = key.lower()
      if lowered in _EMAIL_ADDRESS_FIELDS or lowered in _CALENDAR_ATTENDEE_FIELDS:
        parsed, err = validate_recipient_domains(
            value,
            normalized_allowed,
            field_name=key,
            require_at_least_one=False,
        )
        if err is not None:
          logger.warning(
              "Blocked external or malformed recipient on tool %s (%s): %s",
              tool_name,
              key,
              err,
          )
          return {
              "status": "ERROR",
              "error_details": err,
          }
        if lowered in _EMAIL_ADDRESS_FIELDS and parsed:
          seen_email_recipient = True

    if not is_calendar and not seen_email_recipient:
      msg = (f"Tool '{tool_name}' requires at least one internal recipient in "
             f"allowed domains ({', '.join(sorted(normalized_allowed))}).")
      logger.warning("Blocked empty recipient call on tool %s: %s", tool_name,
                     msg)
      return {
          "status": "ERROR",
          "error_details": msg,
      }

    return None

  return _before_tool_callback
