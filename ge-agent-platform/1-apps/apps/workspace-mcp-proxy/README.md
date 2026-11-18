# Google Workspace Internal-Domain Guardrail (Cloud Run MCP Proxy & ADK Callback)

This application implements a deterministic **internal-domain-only egress boundary** for mutative Gmail and Google Calendar actions invoked by **Gemini Enterprise** or custom **Agent Development Kit (ADK)** agents:

1. **Native Read-Only Federation + Custom Mutative MCP Proxy (Gemini Enterprise):**
   - Native `google_mail`, `google_calendar`, and `google_drive` connectors in Gemini Enterprise are configured strictly in `FEDERATED` search mode (`connector_modes = ["FEDERATED"]`) with zero mutative actions enabled.
   - Outbound email and calendar actions are exposed exclusively through this private **Cloud Run v2** Streamable HTTP MCP server (`server.py`), registered in **Agent Registry** and routed from Gemini Enterprise through the **Egress Agent Gateway** (`AGENT_TO_ANYWHERE`) over Private Service Connect Interface (PSC-I) into the Shared VPC.
   - Before calling Gmail (`users.messages.send`, `users.drafts.create`) or Google Calendar (`events.insert`), [`src/domain_guardrail.py`](./src/domain_guardrail.py) parses every `to`, `cc`, `bcc`, and `attendees` value with Python's RFC-5322 `email.utils.getaddresses` parser and **hard-blocks any recipient outside `ALLOWED_RECIPIENT_DOMAINS`** (including display-name spoofing and header-newline injection).
2. **Human-in-the-Loop (HITL) vs. Automated Internal Sends:**
   - **Interactive HITL + External Hard-Block (Default):** `send_internal_email` and `create_internal_calendar_event` declare `readOnlyHint: false` and `destructiveHint: true` in their MCP tool annotations. Gemini Enterprise therefore pauses for user HITL confirmation on every internal send, while any external domain is deterministically rejected by the Cloud Run proxy even if prompt-injected or mistakenly approved.
   - **Unattended Scheduled / Automated Internal Sends (Opt-In):** Setting `ENABLE_AUTOMATED_INTERNAL_SEND_TOOL=true` exposes `send_automated_internal_email` (`readOnlyHint: true`) for Scheduled Chat Agent runs that need unattended delivery without pausing on a confirmation card, while still enforcing `ALLOWED_RECIPIENT_DOMAINS` (and restricting delivery strictly to the caller's own verified Gmail address when `AUTOMATED_SEND_SELF_ONLY=true`).
3. **ADK `before_tool_callback` Guardrail (Vertex AI Agent Engine / Cloud Run ADK Agents):**
   - Custom ADK agents can import `create_workspace_domain_before_tool_callback` from [`src/domain_guardrail.py`](./src/domain_guardrail.py) directly on `LlmAgent(before_tool_callback=...)` (optionally paired with `FunctionTool(..., require_confirmation=True)`) to short-circuit external recipient tool calls in-process before execution:

```python
from google.adk.agents import LlmAgent
from google.adk.tools import FunctionTool
from src.domain_guardrail import create_workspace_domain_before_tool_callback

agent = LlmAgent(
    name="internal_comms_agent",
    model="gemini-2.5-pro",
    tools=[FunctionTool(send_internal_email, require_confirmation=True)],
    before_tool_callback=create_workspace_domain_before_tool_callback(
        ["example.com"]
    ),
)
```

## Run Unit Tests Locally

```shell
cd ge-agent-platform/1-apps/apps/workspace-mcp-proxy
uv run --all-groups pytest
```
