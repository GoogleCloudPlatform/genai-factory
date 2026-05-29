# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "google-cloud-storage>=2.19.0",
#     "markdown>=3.8",
#     "pydantic-settings>=2.10.1",
#     "python-slugify>=8.0.4",
#     "python-frontmatter>=1.1.0",
#     "pyyaml>=6.0.2",
#     "requests>=2.34.2",
#     "retry>=0.9.2",
#     "retrying>=1.4.2",
#     "tabulate>=0.9.0",
#     "typer>=0.19.2",
#     "rich",
#     "pyopenssl",
# ]
# ///

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

import base64
import io
import json
import uuid
import logging
import os
import re
import shutil
import subprocess
import time
import zipfile
from pathlib import Path
from typing import Optional

import frontmatter
import google.auth
import markdown
import requests
import typer
from google.auth import impersonated_credentials
from google.auth.transport.requests import Request
from google.cloud import storage
from rich.logging import RichHandler
from rich.progress import track
from slugify import slugify

logging.getLogger("google_genai").setLevel(logging.WARNING)
logging.getLogger("httpx").setLevel(logging.WARNING)

logging.basicConfig(level=logging.INFO,
                    handlers=[RichHandler(show_path=False, show_level=False)])
logger = logging.getLogger("agentutil")

_logged_impersonation = False


def get_credentials():
  """Gets credentials, optionally impersonating a service account or using an access token."""
  global _logged_impersonation
  credentials, project = google.auth.default()

  access_token = os.environ.get("ACCESS_TOKEN")
  if access_token:
    from google.oauth2.credentials import Credentials as OAuth2Credentials
    credentials = OAuth2Credentials(token=access_token)
    return credentials, project

  impersonate_sa = os.environ.get("IMPERSONATE_SERVICE_ACCOUNT")
  if impersonate_sa:
    if not _logged_impersonation:
      print(f"Impersonating service account: {impersonate_sa}")
      _logged_impersonation = True
    credentials = impersonated_credentials.Credentials(
        source_credentials=credentials, target_principal=impersonate_sa,
        target_scopes=["https://www.googleapis.com/auth/cloud-platform"],
        lifetime=3600)
  return credentials, project


def get_current_user_email(credentials) -> str:
  """Retrieves the email of the currently authenticated user."""
  if not credentials.valid:
    try:
      credentials.refresh(Request())
    except Exception as e:
      logger.debug(f"Could not refresh credentials: {e}")

  try:
    r = requests.get("https://www.googleapis.com/oauth2/v3/userinfo",
                     headers={"Authorization": f"Bearer {credentials.token}"})
    if r.status_code == 200:
      return r.json().get('email')
  except:
    pass

  try:
    email = subprocess.check_output(
        ["gcloud", "config", "get-value", "account"], text=True).strip()
    if email:
      return email
  except:
    pass

  logger.warning(
      "Could not determine current user email. Permission check might differ from script."
  )
  return "unknown"


def has_sa_user_role(sa_email: str, user_email: str, project_id: str | None,
                     credentials) -> bool:
  """Checks if the user has Service Account User role on the SA or Project."""
  if not user_email or user_email == "unknown":
    return True  # Can't check

  if not credentials.valid:
    try:
      credentials.refresh(Request())
    except Exception as e:
      logger.debug(f"Could not refresh credentials: {e}")

  headers = {
      "Authorization": f"Bearer {credentials.token}",
      "Content-Type": "application/json",
      "X-Goog-User-Project": project_id or ""
  }

  url = f"https://iam.googleapis.com/v1/projects/-/serviceAccounts/{sa_email}:testIamPermissions"
  payload = {"permissions": ["iam.serviceAccounts.actAs"]}

  try:
    r = requests.post(url, headers=headers, json=payload)
    if r.status_code == 200:
      permissions = r.json().get('permissions', [])
      return "iam.serviceAccounts.actAs" in permissions
    else:
      logger.warning(
          f"Failed to test permissions for {sa_email}: {r.status_code} {r.text}"
      )
  except Exception as e:
    logger.error(f"Error testing permissions for {sa_email}: {e}")

  return False


class CesAgent:

  def __init__(self, local_agent_path: str):
    self.local_agent_path = Path(local_agent_path)
    self.credentials, self.project_id = get_credentials()

  def _get_headers(self):
    if not self.credentials.valid:
      try:
        self.credentials.refresh(Request())
      except Exception as e:
        logger.debug(f"Could not refresh credentials: {e}")
    return {
        "Authorization": f"Bearer {self.credentials.token}",
        "Content-Type": "application/json",
        "X-Goog-User-Project": self.project_id or "",
    }

  def replace_data_store(self, tool_name: str, data_store_id: str):
    """Replace a data store reference in environment.json."""
    env_path = self.local_agent_path / "environment.json"
    if not env_path.exists():
      raise FileNotFoundError(
          f"environment.json not found in {self.local_agent_path}")

    with open(env_path, "r") as f:
      data = json.load(f)

    try:
      tool_config = data.get("tools", {}).get(tool_name)
      if not tool_config:
        raise ValueError(
            f"Tool '{tool_name}' not found in environment.json tools.")

      ds_tool = tool_config.get("dataStoreTool")
      if not ds_tool:
        raise ValueError(
            f"Tool '{tool_name}' is not a Data Store tool (missing 'dataStoreTool')."
        )

      sources = ds_tool.get("engineSource", {}).get("dataStoreSources", [])
      if not sources:
        raise ValueError(f"No dataStoreSources found in tool '{tool_name}'.")

      if len(sources) > 1:
        raise ValueError(
            f"Tool '{tool_name}' has multiple data store sources. Only one is supported."
        )

      sources[0]["dataStore"]["name"] = data_store_id

      with open(env_path, "w") as f:
        json.dump(data, f, indent=4)

      logger.info(
          f"✅ Replaced Data Store reference in tool {tool_name} with: {data_store_id}"
      )

    except Exception as e:
      logger.error(f"❌ Failed to replace data store: {e}")
      raise

  def replace_sa_auth(self, tool_name: str, sa_email: str):
    """Replace Service Account authentication for a tool in environment.json."""
    env_path = self.local_agent_path / "environment.json"
    if not env_path.exists():
      raise FileNotFoundError(
          f"environment.json not found in {self.local_agent_path}")

    with open(env_path, "r") as f:
      data = json.load(f)

    try:
      toolsets = data.get("toolsets", {})
      toolset = toolsets.get(tool_name)
      if not toolset:
        raise ValueError(
            f"Toolset '{tool_name}' not found in environment.json toolsets.")

      openapi = toolset.get("openApiToolset")
      if not openapi:
        raise ValueError(
            f"Toolset '{tool_name}' does not appear to be an OpenAPI toolset.")

      auth_config = openapi.get("apiAuthentication",
                                {}).get("serviceAccountAuthConfig")
      if not auth_config:
        raise ValueError(
            f"serviceAccountAuthConfig not found for toolset '{tool_name}'.")

      auth_config["serviceAccount"] = sa_email

      with open(env_path, "w") as f:
        json.dump(data, f, indent=4)

      logger.info(
          f"✅ Updated Service Account for tool {tool_name} to: {sa_email}")

    except Exception as e:
      logger.error(f"❌ Failed to update SA auth for {tool_name}: {e}")
      raise

  def _normalize_bucket_name(self, bucket_name: str) -> str:
    if bucket_name.startswith("gs://"):
      bucket_name = bucket_name[5:]
    return bucket_name.split("/", 1)[0]

  def _normalize_agent_id(self, agent_id: str) -> str:
    """Normalizes an agent ID or URL to a fully qualified agent resource name."""
    if agent_id.startswith("http"):
      if "/projects/" in agent_id:
        path = "projects/" + agent_id.split("/projects/", 1)[1]
        path = path.split("?")[0].split("#")[0]
        parts = path.split("/")
        if len(parts) >= 6:
          agent_id = "/".join(parts[:6])
        else:
          agent_id = path
    return agent_id

  def push(self, agent_id: str, bucket_name: str):
    """Push (upload and import) the local agent to the remote CES agent."""
    agent_id = self._normalize_agent_id(agent_id)
    bucket_name = self._normalize_bucket_name(bucket_name)

    self._check_sa_permissions()

    app_json = self.local_agent_path / "app.json"
    app_yaml = self.local_agent_path / "app.yaml"
    if not app_json.exists() and not app_yaml.exists():
      raise ValueError(
          f"Invalid agent export: {self.local_agent_path} must contain app.json or app.yaml"
      )

    logger.info(f"Zipping agent from {self.local_agent_path}")
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
      for root, _, files in os.walk(self.local_agent_path):
        for file in files:
          file_path = Path(root) / file
          local_arcname = file_path.relative_to(self.local_agent_path)
          arcname = Path("agent") / local_arcname
          zip_file.write(file_path, arcname)
    zip_buffer.seek(0)

    blob_name = f"agentutil/push/{slugify(agent_id)}_{int(time.time())}.zip"
    gcs_uri = f"gs://{bucket_name}/{blob_name}"

    logger.info(f"Uploading to {gcs_uri}")
    storage_client = storage.Client(project=self.project_id,
                                    credentials=self.credentials)
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    blob.upload_from_file(zip_buffer)

    logger.info(f"Triggering import for {agent_id}")

    if "/apps/" in agent_id:
      parent_path = agent_id.rsplit("/apps/", 1)[0]
      app_id = agent_id.rsplit("/apps/", 1)[1]
      url = f"https://ces.googleapis.com/v1beta/{parent_path}/apps:importApp"
      payload = {
          "appId": app_id,
          "gcsUri": gcs_uri,
          "importOptions": {
              "conflictResolutionStrategy": "OVERWRITE"
          },
      }
    else:
      raise ValueError(
          "agent_id must be in format projects/.../locations/.../apps/...")

    response = requests.post(url, headers=self._get_headers(), json=payload)
    if response.status_code != 200:
      raise RuntimeError(f"Import request failed: {response.text}")

    lro = response.json()
    op_name = lro.get("name")
    if not op_name:
      raise RuntimeError(f"No operation name in response: {lro}")

    try:
      op_result = self._poll_operation(op_name)
      response_data = op_result.get("response", {})
      warnings = response_data.get("warnings", [])
      if warnings:
        for warning in warnings:
          logger.warning(f"⚠️ {warning}")

      logger.info("✅ Push completed successfully.")
    except Exception as e:
      logger.error(f"❌ Push failed: {e}")
      raise

  def pull(self, agent_id: str, bucket_name: str,
           environment_id: Optional[str] = None):
    """Pull (export) remote CES agent to local path."""
    agent_id = self._normalize_agent_id(agent_id)
    bucket_name = self._normalize_bucket_name(bucket_name)

    blob_name = f"agentutil/pull/{slugify(agent_id)}_{int(time.time())}.zip"
    gcs_uri = f"gs://{bucket_name}/{blob_name}"

    url = f"https://ces.googleapis.com/v1beta/{agent_id}:exportApp"
    payload = {"gcsUri": gcs_uri, "exportFormat": "JSON"}

    logger.info(f"Exporting agent {agent_id} to {gcs_uri}")
    response = requests.post(url, headers=self._get_headers(), json=payload)

    if response.status_code != 200:
      raise RuntimeError(f"Export request failed: {response.text}")

    lro = response.json()
    op_name = lro.get("name")
    if not op_name:
      raise RuntimeError(f"No operation name in response: {lro}")

    try:
      self._poll_operation(op_name)

      logger.info("Downloading exported agent...")
      if self.local_agent_path.exists():
        shutil.rmtree(self.local_agent_path)
      self.local_agent_path.mkdir(parents=True, exist_ok=True)

      storage_client = storage.Client(project=self.project_id,
                                      credentials=self.credentials)
      bucket = storage_client.bucket(bucket_name)
      blob = bucket.blob(blob_name)

      zip_bytes = blob.download_as_bytes()

      with zipfile.ZipFile(io.BytesIO(zip_bytes)) as z:
        top_level_dirs = {
            item.split("/")[0] for item in z.namelist() if "/" in item
        }

        if len(top_level_dirs) == 1:
          z.extractall(self.local_agent_path)
          params = [p for p in self.local_agent_path.iterdir() if p.is_dir()]
          if len(params) == 1 and not any(
              f.is_file()
              for f in self.local_agent_path.iterdir()
              if f.name != ".DS_Store"):
            subdir = params[0]
            for item in subdir.iterdir():
              shutil.move(str(item), str(self.local_agent_path))
            subdir.rmdir()
        else:
          z.extractall(self.local_agent_path)

      logger.info(f"✅ Pulled agent to {self.local_agent_path}")
    except Exception as e:
      logger.error(f"❌ Pull failed: {e}")
      raise

  def _poll_operation(self, operation_name: str):
    logger.info(f"Polling operation: {operation_name}")
    while True:
      url = f"https://ces.googleapis.com/v1beta/{operation_name}"
      response = requests.get(url, headers=self._get_headers())
      if response.status_code != 200:
        raise RuntimeError(f"Poll failed: {response.text}")

      op_data = response.json()
      if op_data.get("done"):
        if "error" in op_data:
          raise RuntimeError(f"Operation failed: {op_data['error']}")
        logger.info("Operation completed.")
        return op_data

      time.sleep(3)

  def _check_sa_permissions(self):
    """Discover SAs in environment.json and check 'Service Account User' role."""
    env_path = self.local_agent_path / "environment.json"
    if not env_path.exists():
      logger.warning("No environment.json found. Skipping permission check.")
      return

    with open(env_path, "r") as f:
      data = json.load(f)

    toolsets = data.get("toolsets", {})
    sas_to_check = set()

    for tool_name, toolset in toolsets.items():
      sa = (toolset.get("openApiToolset",
                        {}).get("apiAuthentication",
                                {}).get("serviceAccountAuthConfig",
                                        {}).get("serviceAccount"))
      if sa:
        sas_to_check.add(sa)

    if not sas_to_check:
      logger.info("No service accounts found in agent configuration.")
      return

    user_email = get_current_user_email(self.credentials)
    logger.info(
        f"Checking permissions for user {user_email} on SAs: {sas_to_check}")

    for sa in sas_to_check:
      if not has_sa_user_role(sa, user_email, self.project_id,
                              self.credentials):
        raise PermissionError(
            f"User {user_email} does not have 'roles/iam.serviceAccountUser' on {sa} or project. Without this permission, the import operation will fail, as the service account is used to authenticate at least one OpenAPI tool in the app."
        )


def process_data_store_documents(source_dir: str, target_dir: str,
                                 gcs_bucket_folder_path: str,
                                 ingest_to_data_store: str = None) -> None:
  """Preprocesses Markdown files for Data Store ingestion."""
  credentials, project = get_credentials()
  if not os.path.isdir(source_dir):
    raise FileNotFoundError(f"Source folder not found: '{source_dir}'")

  os.makedirs(target_dir, exist_ok=True)
  logger.debug(f"Destination folder ensured: '{target_dir}'")

  if not gcs_bucket_folder_path.startswith("gs://"):
    raise ValueError(
        f"GCS bucket path must start with 'gs://'. Got: '{gcs_bucket_folder_path}'"
    )

  gcs_bucket_folder_path = f"{gcs_bucket_folder_path.rstrip('/')}/"

  gcs_path_components = gcs_bucket_folder_path[len("gs://"):].split('/', 1)
  gcs_bucket_name = gcs_path_components[0]
  gcs_blob_prefix = gcs_path_components[1] if len(
      gcs_path_components) > 1 else ""

  if gcs_blob_prefix and not gcs_blob_prefix.endswith('/'):
    gcs_blob_prefix += '/'

  logger.info(
      f"Parsed GCS path: Bucket='{gcs_bucket_name}', Blob Prefix='{gcs_blob_prefix}'"
  )

  jsonl_entries = []
  local_files_to_upload = []

  logger.info("\nStarting Markdown file processing...")
  markdown_files_found = False
  for filename in track(os.listdir(source_dir)):
    if not filename.endswith(".md"):
      continue

    markdown_files_found = True
    md_filepath = os.path.join(source_dir, filename)
    base_name = os.path.splitext(filename)[0]
    html_filename = f"{base_name}.html"
    html_filepath = os.path.join(target_dir, html_filename)

    logger.info(f"  Processing '{filename}'...")

    try:
      post = frontmatter.load(md_filepath)
      raw_metadata = post.metadata
      md_content = post.content

      struct_data = {}

      title = raw_metadata.get('title')
      if title:
        struct_data['title'] = title

      additional_metadata = raw_metadata.get('metadata')
      if isinstance(additional_metadata, dict):
        struct_data.update(additional_metadata)

      html_content = markdown.markdown(md_content)

      with open(html_filepath, 'w', encoding='utf-8') as f:
        f.write(html_content)
      logger.info(f"    - Converted to HTML and saved: '{html_filepath}'")
      local_files_to_upload.append(html_filepath)

      gcs_document_uri = f"{gcs_bucket_folder_path}{html_filename}"

      jsonl_entry = {
          "id": base_name,
          "structData": struct_data,
          "content": {
              "mimeType": "text/html",
              "uri": gcs_document_uri
          }
      }
      jsonl_entries.append(jsonl_entry)
      logger.info(
          f"    - Prepared JSONL entry for ID: '{base_name}' (Title: '{title}')"
      )

    except Exception as e:
      logger.error(f"  Error processing '{filename}': {e}. Skipping.")
      continue

  if not markdown_files_found:
    logger.warning("No Markdown files (.md) found in the source folder.")

  jsonl_output_filename = "documents.jsonl"
  jsonl_output_path = os.path.join(target_dir, jsonl_output_filename)

  with open(jsonl_output_path, 'w', encoding='utf-8') as f:
    for entry in jsonl_entries:
      f.write(json.dumps(entry) + '\n')
  logger.info(
      f"\nGenerated JSONL manifest: '{jsonl_output_path}' with {len(jsonl_entries)} entries."
  )
  local_files_to_upload.append(jsonl_output_path)

  logger.info(
      f"\nUploading generated files to GCS bucket: '{gcs_bucket_folder_path}'..."
  )
  storage_client = storage.Client(project=project, credentials=credentials)
  bucket = storage_client.bucket(gcs_bucket_name)

  for local_file_path in track(local_files_to_upload):
    relative_path_from_dest = os.path.relpath(local_file_path, target_dir)
    gcs_blob_name = gcs_blob_prefix + relative_path_from_dest

    blob = bucket.blob(gcs_blob_name)
    blob.upload_from_filename(local_file_path)
    print(
        f"  Uploaded '{local_file_path}' to 'gs://{gcs_bucket_name}/{gcs_blob_name}'"
    )

  if ingest_to_data_store:
    logger.info(
        f"\nTriggering ingestion to Data Store: '{ingest_to_data_store}'...")

    gcs_jsonl_uri = f"{gcs_bucket_folder_path}{jsonl_output_filename}"

    try:
      import_documents(ingest_to_data_store, gcs_jsonl_uri)
      logger.info("  Ingestion request successfully submitted.")
    except Exception as e:
      logger.error(f"  Error submitting ingestion request: {e}")
      raise e


def import_documents(full_data_store_name: str, gcs_uri: str) -> None:
  """Imports documents into a Discovery Engine Data Store from a GCS source."""
  match = re.search(r'/locations/([^/]+)/', full_data_store_name)
  if not match:
    raise ValueError(
        f"Could not extract location from data store name: '{full_data_store_name}'"
    )

  location = match.group(1)

  if location == "global":
    api_endpoint = f"https://discoveryengine.googleapis.com/v1/{full_data_store_name}/branches/0/documents:import"
  else:
    api_endpoint = f"https://{location}-discoveryengine.googleapis.com/v1/{full_data_store_name}/branches/0/documents:import"

  logger.debug(f"Import API Endpoint: {api_endpoint}")

  credentials, project = get_credentials()
  auth_req = google.auth.transport.requests.Request()
  try:
    credentials.refresh(auth_req)
  except Exception as e:
    logger.debug(f"Could not refresh credentials: {e}")
  access_token = credentials.token

  headers = {
      "Authorization": f"Bearer {access_token}",
      "Content-Type": "application/json",
      "X-Goog-User-Project": project
  }

  body = {
      "gcsSource": {
          "inputUris": [gcs_uri],
          "dataSchema": "document"
      },
      "reconciliationMode": "FULL"
  }

  response = requests.post(api_endpoint, headers=headers, json=body)

  if response.status_code != 200:
    logger.error(
        f"Import failed with status code {response.status_code}: {response.text}"
    )
    response.raise_for_status()

  logger.info(
      f"Import started. Response: {json.dumps(response.json(), indent=2)}")


app = typer.Typer(name='agentutil',
                  help='A set of utilities to develop CX Agent Studio Apps.')

ces_app = typer.Typer()
app.add_typer(ces_app, name="ces", help="Utilities for CES platform")
ces_agent_app = typer.Typer()
ces_app.add_typer(ces_agent_app, name="agent", help="Manage CES agents")
documents_app = typer.Typer()
app.add_typer(documents_app, name="data-store",
              help="Process text documents and populate Data Stores.")


@ces_agent_app.command("replace-data-store")
def replace_data_store_ces(target_agent_dir: str, tool_name: str,
                           data_store_id: str):
  """Replace a data store reference in environment.json."""
  try:
    agent = CesAgent(target_agent_dir)
    agent.replace_data_store(tool_name, data_store_id)
  except Exception as e:
    logger.error(f"Error: {e}")
    raise typer.Exit(code=1)


@ces_agent_app.command()
def replace_sa_auth(target_agent_dir: str, tool_name: str, sa_email: str):
  """Replace Service Account authentication for a tool."""
  try:
    agent = CesAgent(target_agent_dir)
    agent.replace_sa_auth(tool_name, sa_email)
  except Exception as e:
    logger.error(f"Error: {e}")
    raise typer.Exit(code=1)


@ces_agent_app.command()
def push(target_dir: str, agent_id: str, bucket: str):
  """Push local agent to remote CES agent."""
  try:
    agent = CesAgent(target_dir)
    agent.push(agent_id, bucket)
  except Exception as e:
    logger.error(f"Error: {e}")
    raise typer.Exit(code=1)


@ces_agent_app.command()
def pull(agent_id: str, target_dir: str, bucket: str, environment: str = None):
  """Pull remote CES agent to local directory."""
  try:
    agent = CesAgent(target_dir)
    agent.pull(agent_id, bucket, environment)
  except Exception as e:
    logger.error(f"Error: {e}")
    raise typer.Exit(code=1)


@documents_app.command('ingest')
def process_data_store_documents_command(source_dir: str, target_dir: str,
                                         gcs_bucket_folder_path: str,
                                         ingest_to: str = None) -> None:
  """Preprocesses Markdown files for Data Store ingestion."""
  try:
    process_data_store_documents(source_dir, target_dir, gcs_bucket_folder_path,
                                 ingest_to)
  except Exception as e:
    logger.error(f"Error: {e}")
    raise typer.Exit(code=1)


def _ensure_base64(cert_str: str) -> str:
  cert_str = cert_str.strip()
  if "---BEGIN CERTIFICATE---" in cert_str:
    return base64.b64encode(cert_str.encode("utf-8")).decode("utf-8")
  try:
    base64.b64decode(cert_str, validate=True)
    return cert_str
  except Exception:
    return base64.b64encode(cert_str.encode("utf-8")).decode("utf-8")


def _parse_ca_certs(allowed_ca_certs: Optional[str]) -> list[dict]:
  if not allowed_ca_certs:
    return []
  cleaned = allowed_ca_certs.strip()
  if cleaned.startswith("[") and cleaned.endswith("]"):
    try:
      parsed_list = json.loads(cleaned)
      if isinstance(parsed_list, list):
        certs_list = []
        for i, cert in enumerate(parsed_list):
          certs_list.append({
              "displayName": f"cert-{i}.der",
              "cert": _ensure_base64(cert)
          })
        return certs_list
    except json.JSONDecodeError:
      cleaned = cleaned[1:-1].replace("'", "").replace('"', "")
  parts = [p.strip() for p in cleaned.split(",") if p.strip()]
  certs_list = []
  for i, cert in enumerate(parts):
    certs_list.append({
        "displayName": f"cert-{i}.der",
        "cert": _ensure_base64(cert)
    })
  return certs_list


@app.command("create-toolset")
def create_toolset(
    target_agent_dir: str,
    toolset_name: str,
    uri: str,
    service_directory: Optional[str] = typer.Option(None,
                                                    "--service-directory"),
    allowed_ca_certs: Optional[str] = typer.Option(None, "--allowed-ca-certs"),
):
  """Creates a new OpenAPI Toolset configuration inside the agent directory."""
  agent_path = Path(target_agent_dir)
  toolsets_dir = agent_path / "toolsets" / toolset_name
  toolsets_dir.mkdir(parents=True, exist_ok=True)

  # 1. Create open_api_schema.yaml
  schema_dir = toolsets_dir / "open_api_toolset"
  schema_dir.mkdir(parents=True, exist_ok=True)
  schema_file = schema_dir / "open_api_schema.yaml"

  yaml_content = """# skip boilerplate check
openapi: 3.0.3
info:
  title: Simple Hello Test API
  description: A basic API to test a hello endpoint.
  version: 1.0.0
servers:
  - url: $env_var
    description: test URL
paths:
  /hello:
    get:
      summary: Returns a greeting message
      description: A simple endpoint that responds with a JSON message saying hello.
      responses:
        '200':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  message:
                    type: string
                    example: "Hello, World!"
"""

  with open(schema_file, "w", encoding="utf-8") as f:
    f.write(yaml_content)

  # 2. Create toolset metadata json file (e.g. default-onprem.json)
  toolset_id = str(uuid.uuid4())
  toolset_json = {
      "name": toolset_id,
      "displayName": toolset_name,
      "openApiToolset": {
          "openApiSchema":
              f"toolsets/{toolset_name}/open_api_toolset/open_api_schema.yaml",
          "apiAuthentication": {
              "serviceAgentIdTokenAuthConfig": {}
          }
      },
      "executionType": "SYNCHRONOUS",
      "description": f"OpenAPI toolset for {toolset_name}"
  }

  if service_directory:
    toolset_json["openApiToolset"]["serviceDirectoryConfig"] = {
        "service": "$env_var"
    }

  ca_certs = _parse_ca_certs(allowed_ca_certs)
  if ca_certs:
    toolset_json["openApiToolset"]["tlsConfig"] = {"caCerts": ca_certs}

  metadata_file = toolsets_dir / f"{toolset_name}.json"
  with open(metadata_file, "w", encoding="utf-8") as f:
    json.dump(toolset_json, f, indent=2)

  # 3. Modify environment.json
  env_path = agent_path / "environment.json"
  if env_path.exists():
    with open(env_path, "r", encoding="utf-8") as f:
      try:
        env_data = json.load(f)
      except json.JSONDecodeError:
        env_data = {}
  else:
    env_data = {}

  if "toolsets" not in env_data:
    env_data["toolsets"] = {}

  normalized_url = uri.strip()
  if not normalized_url.startswith(("http://", "https://")):
    normalized_url = f"https://{normalized_url}"

  toolset_env_config = {"openApiToolset": {"url": normalized_url}}

  if service_directory:
    toolset_env_config["openApiToolset"]["serviceDirectoryConfig"] = {
        "service": service_directory
    }

  env_data["toolsets"][toolset_name] = toolset_env_config

  with open(env_path, "w", encoding="utf-8") as f:
    json.dump(env_data, f, indent=4)

  logger.info(
      f"✅ Successfully created toolset '{toolset_name}' in {metadata_file} and updated environment.json"
  )


def main():
  app()


if __name__ == "__main__":
  main()
