# GECX Developer Flows

This document details the developer workflows for managing data and agent configurations after the initial Terraform deployment. Each step highlights the native commands used, the variables involved, and their producers.

## 1. Setup Authentication

Before executing any updates, developers must obtain an authentication token, typically by impersonating the Terraform deployment service account.

### Step 1: Generate Bearer Token

- **Command:** `gcloud auth print-access-token`
- **Variables:**
  - `var.service_accounts["project/iac-rw"].email` (Produced by Terraform variables/state)
- **Action:** Exported as `$BEARER_TOKEN` in the environment.

## 2. Data Update Flow

This flow updates the data stores used by the conversational agent.

### FAQ Data Update

#### Step 1: Upload FAQ CSV

- **Command:** `gcloud storage cp`
- **Variables:**
  - `module.ds-bucket.url` (Produced by Terraform module `ds-bucket`)
  - `var.service_accounts["project/iac-rw"].email` (Produced by Terraform)
  - `var.project_config.id` (Produced by Terraform)

#### Step 2: Import FAQ Data to Discovery Engine

- **Command:** `curl -X POST`
- **Variables:**
  - `local.uris.ds_faq` (Produced by Terraform `module.dialogflow` outputs)
  - `$BEARER_TOKEN` (Produced by Setup Authentication flow)
  - `var.project_config.id` (Produced by Terraform)
  - `module.ds-bucket.url` (Produced by Terraform module `ds-bucket`)

### Knowledge Base (KB) Data Update

#### Step 1: Process and Upload KB Documents

This step utilizes the local `agentutil.py process-documents` CLI tool to preprocess markdown files and upload them to GCS.

- **Command:** `uv run scripts/agentutil/agentutil.py process-documents`
- **Variables:**
  - `module.ds-bucket.url` (Produced by Terraform module `ds-bucket`)

**`agentutil.py process-documents` Subflow:**

1. **Read Markdown Files:**
   - **Operation:** Scans the provided source directory (e.g., `./data/ds-kb/`) for all `.md` files.
2. **Convert to HTML & Extract Metadata:**
   - **Operation:** For each markdown file, it parses the content, extracts the title from the first `# H1` heading (falling back to the filename if not found), and converts the markdown content to HTML.
   - **Command/API:** Python `markdown.markdown()` library.
3. **Save HTML Locally:**
   - **Operation:** Writes the generated HTML files to the destination directory (e.g., `./build/data/ds-kb/`).
4. **Generate JSONL Manifest:**
   - **Operation:** Creates a `documents.jsonl` manifest file required by the Discovery Engine. Each entry maps a document ID (filename) to its extracted title (`structData.title`) and target GCS URI (`content.uri`).
5. **Upload to GCS:**
   - **Operation:** Because the `--upload` flag is used, it uploads all generated `.html` files and the `documents.jsonl` manifest directly to the Data Store GCS bucket.
   - **Command/API:** Google Cloud Storage Python Client (`google.cloud.storage.Client`).
   - **Variables:** Extracts bucket name and blob prefix from the provided GCS path (e.g., `${module.ds-bucket.url}/ds-kb/`).

#### Step 2: Import KB Data to Discovery Engine

- **Command:** `curl -X POST`
- **Variables:**
  - `local.uris.ds_kb` (Produced by Terraform `module.dialogflow` outputs)
  - `$BEARER_TOKEN` (Produced by Setup Authentication flow)
  - `var.project_config.id` (Produced by Terraform)
  - `module.ds-bucket.url` (Produced by Terraform module `ds-bucket`)

## 3. Agent Update Flow

This flow packages a local agent variant, patches it with the correct data store IDs, and deploys it to Dialogflow CX.

#### Step 1: Prepare Build Directory & Copy Variant

- **Command:** `rm -rf`, `mkdir -p`, `cp -r`
- **Variables:**
  - `local.agent_dir` (Static Terraform local)
  - `var.agent_configs.variant` (Produced by Terraform variables)

#### Step 2: Patch Data Store References

This step utilizes the local `agentutil.py replace-data-store` CLI tool to modify the agent's files in-place, updating data store connections with actual IDs provisioned by Terraform.

- **Command:** `uv run scripts/agentutil/agentutil.py replace-data-store`
- **Variables:**
  - `local.agent_dir` (Static Terraform local)
  - `module.dialogflow.data_stores["kb"].name` (Produced by Terraform `module.dialogflow`)

**`agentutil.py replace-data-store` Subflow:**

1. **Locate Tool Configuration:**
   - **Operation:** Resolves the path to the specific tool's JSON configuration file within the local agent directory (e.g., `<agent_dir>/tools/<tool_name>/<tool_name>.json`).
2. **Parse JSON Specification:**
   - **Operation:** Opens and parses the JSON file containing the tool's specification.
   - **Command/API:** Python `json.load()`.
3. **Find Target Data Store Connection:**
   - **Operation:** Iterates through the `dataStoreConnections` array inside the `dataStoreSpec` object to find a connection matching the specified `data_store_type` (e.g., `UNSTRUCTURED`).
4. **Inject New Data Store ID:**
   - **Operation:** Replaces the existing `dataStore` value with the actual target ID (`data_store_id`) provided as an argument.
5. **Save Updated Configuration:**
   - **Operation:** Writes the modified JSON structure back to the file system, overwriting the original file in-place.
   - **Command/API:** Python `json.dump()` with indentation.

#### Step 3: Package Agent

- **Command:** `zip -r`
- **Variables:**
  - `local.agent_dir` (Static Terraform local)

#### Step 4: Upload Agent Package to GCS

- **Command:** `gcloud storage cp`
- **Variables:**
  - `local.agent_dir` (Static Terraform local)
  - `module.build-bucket.url` (Produced by Terraform module `build-bucket`)
  - `var.agent_configs.variant` (Produced by Terraform variables)
  - `var.service_accounts["project/iac-rw"].email` (Produced by Terraform)
  - `var.project_config.id` (Produced by Terraform)

#### Step 5: Deploy Agent via Restore API

- **Command:** `curl -X POST`
- **Variables:**
  - `local.uris.agent` (Produced by Terraform `module.dialogflow` outputs)
  - `$BEARER_TOKEN` (Produced by Setup Authentication flow)
  - `var.project_config.id` (Produced by Terraform)
  - `module.build-bucket.url` (Produced by Terraform module `build-bucket`)
  - `var.agent_configs.variant` (Produced by Terraform variables)

## 4. Query Flow (Validation)

This flow validates the agent's deployment by sending a query.

#### Step 1: Send Test Query

- **Command:** `curl -X POST`
- **Variables:**
  - `local.uris.agent_query` (Produced by Terraform `module.dialogflow` outputs)
  - `$BEARER_TOKEN` (Produced by Setup Authentication flow)
  - `var.project_config.id` (Produced by Terraform)
  - `var.agent_configs.language` (Produced by Terraform variables)

## 5. Pull Agent Flow (Reverse Sync)

This flow synchronizes changes made in the Dialogflow CX UI back to the local repository.

#### Step 1: Export and Extract Agent

- **Command:** `uv run scripts/agentutil/agentutil.py pull_agent`
- **Variables:**
  - `AGENT_REMOTE` (Provided by the User)
  - `AGENT_VARIANT` (Provided by the User)

## 6. Create Webhook Flow

This flow creates a new webhook configuration file dynamically within an agent variant directory, assigning a unique UUID and structuring the required fields.

#### Step 1: Generate Webhook Configuration

- **Command:** `uv run scripts/agentutil/agentutil.py create-webhook`
- **Variables:**
  - `TARGET_AGENT_DIR` (Provided by the User, e.g., `./data/agents/default`)
  - `DISPLAY_NAME` (Provided by the User)
  - `URI` (Provided by the User)
  - `--service-directory` (Optional, provided by the User)
  - `--allowed-ca-certs` (Optional, provided by the User)
  - `--timeout` (Optional, provided by the User)

**`agentutil.py create-webhook` Subflow:**

1. **Ensure Webhook Directory Exists:**
   - **Operation:** Ensures the `webhooks/` directory exists under the target agent directory.
2. **Generate UUID:**
   - **Operation:** Generates a random UUID (version 4) to uniquely identify the webhook instance.
   - **Command/API:** Python `uuid.uuid4()`.
3. **Construct JSON Structure:**
   - **Operation:** Builds the JSON configuration for the webhook based on the provided generic Cloud Function URL or Service Directory configuration inputs.
4. **Save Webhook Locally:**
   - **Operation:** Writes the generated JSON structure to `{TARGET_AGENT_DIR}/webhooks/{DISPLAY_NAME}.json`.
