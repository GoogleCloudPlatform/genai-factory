# Agent Utility CLI (`agentutil.py`)

A Command Line Interface (CLI) tool designed to manage and patch Google Cloud Conversational Agents. It provides utilities for pulling, patching and pushing agents, and for preprocessing documents before ingestion.

## Prerequisites
- Python 3.x
- Required packages (can typically be managed via `uv`, e.g., `uv run scripts/agentutil/agentutil.py ...`):
  - `click`
  - `markdown`
  - `google-cloud-dialogflow-cx`
  - `google-cloud-storage`
- Authenticated Google Cloud session (e.g., via `gcloud auth application-default login` or environment variable service accounts).

## Usage Overview

Run the tool using Python (or via your environment manager like `uv`):

```bash
python scripts/agentutil/agentutil.py [COMMAND] [OPTIONS] [ARGUMENTS]
```

Alternatively, if utilizing `uv` for the repository:
```bash
uv run scripts/agentutil/agentutil.py [COMMAND] [OPTIONS] [ARGUMENTS]
```

## Commands

### 1. `pull-agent`

Exports a Dialogflow CX agent to a local directory. It handles downloading the agent, creating backups of existing local agents, and extracting the JSON package.

**Usage:**
```bash
python scripts/agentutil/agentutil.py pull-agent [OPTIONS] AGENT_NAME TARGET_DIR
```

**Arguments:**
- `AGENT_NAME`: The fully qualified name of the agent to export. Format: `projects/<PROJECT>/locations/<LOCATION>/agents/<AGENT-ID>`
- `TARGET_DIR`: The local directory where the agent will be exported and extracted.

**Options:**
- `--environment`, `-e`: The specific environment to export (e.g., `environments/draft`). If not specified, the draft flow is exported by default.

**Example:**
```bash
python scripts/agentutil/agentutil.py pull-agent projects/my-proj/locations/us-central1/agents/my-agent-id ./my-exported-agent
```

### 2. `replace-data-store`

Replaces a data store reference in a specified tool's configuration. This command modifies the exported agent files **in-place**.

**Usage:**
```bash
python scripts/agentutil/agentutil.py replace-data-store TARGET_AGENT_DIR TOOL_NAME DATA_STORE_TYPE DATA_STORE_ID
```

**Arguments:**
- `TARGET_AGENT_DIR`: The local directory of the exported agent.
- `TOOL_NAME`: The name of the tool whose data store connection needs updating (e.g., the folder name inside `tools/`).
- `DATA_STORE_TYPE`: The type of data store connection to replace. Valid options are: `STRUCTURED`, `UNSTRUCTURED`, or `PUBLIC_WEB`.
- `DATA_STORE_ID`: The actual target ID (or full resource name) of the new data store.

**Example:**
```bash
python scripts/agentutil/agentutil.py replace-data-store ./my-exported-agent my_tool_name UNSTRUCTURED projects/123/locations/global/collections/default_collection/dataStores/new-id
```

### 3. `process-documents`

Preprocesses Markdown files for Data Store ingestion. It converts `.md` files to `.html`, extracts titles (from the first `# H1` tag or falls back to filename), generates a `documents.jsonl` manifest, and can optionally upload the processed files directly to Google Cloud Storage (GCS).

**Usage:**
```bash
python scripts/agentutil/agentutil.py process-documents [OPTIONS] SOURCE_DIR DEST_DIR GCS_PATH
```

**Arguments:**
- `SOURCE_DIR`: Local directory containing the raw `.md` files.
- `DEST_DIR`: Local directory where generated `.html` files and the `documents.jsonl` manifest will be saved.
- `GCS_PATH`: The target GCS path where documents will be hosted (e.g., `gs://my-bucket/my-docs/`).

**Options:**
- `--upload`: If provided, the tool automatically uploads all generated `.html` files and the `documents.jsonl` manifest to the specified `GCS_PATH`.

**Example:**
```bash
python scripts/agentutil/agentutil.py process-documents ./docs ./processed gs://my-bucket/my-docs/ --upload
```

### 4. `create-webhook`

Creates a new webhook configuration JSON file directly within the agent directory's `webhooks/` folder. It automatically generates a unique UUID for the webhook instance.

**Usage:**
```bash
python scripts/agentutil/agentutil.py create-webhook [OPTIONS] TARGET_AGENT_DIR DISPLAY_NAME URI
```

**Arguments:**
- `TARGET_AGENT_DIR`: The local directory of the exported agent.
- `DISPLAY_NAME`: The display name of the webhook to be created.
- `URI`: The target URI of the generic web service.

**Options:**
- `--service-directory`: The Service Directory service name if the webhook is routed via Service Directory (e.g., `projects/.../services/...`).
- `--allowed-ca-certs`: Allowed CA certificates for Service Directory (can be specified multiple times).
- `--timeout`: Timeout in seconds for the webhook response. Default is `5`.

**Example:**
```bash
python scripts/agentutil/agentutil.py create-webhook ./my-agent my-webhook https://us-central1-my-project.cloudfunctions.net/webhook --timeout 10
```

## Backup & Safety
- The tool maintains internal directories (`.agentutil/agent_backups/` from your current working directory) to safely back up any existing agent directories before overwriting them when running `pull-agent`.
