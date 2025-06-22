# Copyright 2025 Google LLC
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
"""
A CLI tool to manage and patch Google Cloud Conversational Agents.

This tool provides utilities for pulling agents, patching data store
references, and preprocessing documents for ingestion.
"""
import datetime
import io
import json
import logging
import shutil
import zipfile
from enum import Enum
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import click
import markdown
from google.cloud import dialogflowcx_v3beta1 as dialogflow
from google.cloud import storage
from google.api_core import exceptions as gcp_exceptions

# --- Setup & Constants ---

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

AGENTUTIL_FOLDER = Path(".agentutil")
AGENT_BACKUP_FOLDER = AGENTUTIL_FOLDER / "agent_backups"


class DataStoreType(Enum):
    """Enumeration for Dialogflow Data Store types."""
    STRUCTURED = 'STRUCTURED'
    UNSTRUCTURED = 'UNSTRUCTURED'
    PUBLIC_WEB = 'PUBLIC_WEB'


# --- Helper Functions ---


def _ensure_agentutil_dirs() -> None:
    """Ensures that the utility and backup directories exist."""
    AGENTUTIL_FOLDER.mkdir(exist_ok=True)
    AGENT_BACKUP_FOLDER.mkdir(exist_ok=True)


def _get_dialogflow_client(agent_name: str) -> dialogflow.AgentsClient:
    """Creates a region-specific Dialogflow CX client."""
    try:
        location_id = agent_name.split('/')[3]
        client_options = {
            "api_endpoint": f"{location_id}-dialogflow.googleapis.com"
        }
        return dialogflow.AgentsClient(client_options=client_options)
    except IndexError:
        raise ValueError(
            "Invalid agent_name format. Expected: "
            "projects/<PROJECT>/locations/<LOCATION>/agents/<AGENT-ID>")


# --- CLI Command Group ---


@click.group()
def main():
    """A CLI for managing Conversational Agents."""
    _ensure_agentutil_dirs()
    pass


# --- CLI Commands ---


@main.command()
@click.argument("agent_name")
@click.argument("target_dir", type=click.Path())
@click.option(
    "--environment",
    "-e",
    default=None,
    help="Environment to export. If not specified, the draft flow is exported."
)
def pull_agent(agent_name: str, target_dir: str, environment: Optional[str]):
    """
    Exports a Dialogflow CX agent to a local directory.

    AGENT_NAME: Fully qualified name of the agent to export.
        (e.g., projects/<PROJECT>/locations/<LOCATION>/agents/<AGENT-ID>)

    TARGET_DIR: Local directory where the agent will be exported.

    Example:
        agentutil pull-agent projects/my-proj/locations/us-central1/agents/my-agent-id ./my-exported-agent
    """
    target_path = Path(target_dir)
    agent_name = agent_name.rstrip('/')
    env_path = f"{agent_name}/environments/{environment}" if environment else None

    try:
        client = _get_dialogflow_client(agent_name)
        click.echo(f"Exporting agent: {click.style(agent_name, bold=True)}...")

        request = dialogflow.ExportAgentRequest(
            name=agent_name,
            data_format=dialogflow.ExportAgentRequest.DataFormat.JSON_PACKAGE,
            environment=env_path,
        )
        operation = client.export_agent(request=request)
        response: dialogflow.ExportAgentResponse = operation.result()

        if response.agent_content:
            if target_path.exists():
                backup_dir = AGENT_BACKUP_FOLDER / target_path.name
                if backup_dir.exists():
                    shutil.rmtree(backup_dir)
                shutil.copytree(target_path, backup_dir)
                click.echo(
                    f"Created backup of existing agent in: {backup_dir}")
                shutil.rmtree(target_path)

            target_path.mkdir(parents=True, exist_ok=True)

            with zipfile.ZipFile(io.BytesIO(response.agent_content),
                                 'r') as zip_ref:
                zip_ref.extractall(target_path)

            click.secho(f"✅ Agent pulled successfully to: {target_path}",
                        fg="green")

        elif response.agent_uri:
            click.echo("Agent exported to Google Cloud Storage.")
            click.secho(f"GCS URI: {response.agent_uri}", fg="yellow")
            click.echo("Please download it from GCS manually.")

        else:
            click.secho("Export failed: No agent content or URI was returned.",
                        fg="red")

    except gcp_exceptions.NotFound as e:
        click.secho(f"Error: Agent or environment not found. Details: {e}",
                    fg="red")
    except Exception as e:
        click.secho(f"An unexpected error occurred during export: {e}",
                    fg="red")


@main.command()
@click.argument("target_agent_dir",
                type=click.Path(exists=True,
                                file_okay=False,
                                dir_okay=True,
                                readable=True))
@click.argument("tool_name")
@click.argument("data_store_type",
                type=click.Choice([t.value for t in DataStoreType],
                                  case_sensitive=False))
@click.argument("data_store_id")
def replace_data_store(target_agent_dir: str, tool_name: str,
                       data_store_type: str, data_store_id: str):
    """
    Replaces a data store reference in a specified tool.

    This command modifies the agent files in-place.

    Example:
        agentutil replace-data-store ./my-exported-agent my_tool_name UNSTRUCTURED projects/.../dataStores/new-id
    """
    agent_path = Path(target_agent_dir)
    tool_file = agent_path / "tools" / tool_name / f"{tool_name}.json"

    if not tool_file.exists():
        click.secho(f"Error: Tool file not found at {tool_file}", fg="red")
        return

    try:
        with tool_file.open('r') as f:
            spec = json.load(f)

        connections = spec.get("dataStoreSpec",
                               {}).get("dataStoreConnections", [])
        if not connections:
            raise ValueError(
                f"Tool '{tool_name}' has no data store connections.")

        found_and_replaced = False
        for conn in connections:
            if conn.get('dataStoreType') == data_store_type.upper():
                conn['dataStore'] = data_store_id
                found_and_replaced = True
                break

        if not found_and_replaced:
            raise ValueError(
                f"Could not find a connection of type '{data_store_type}'.")

        with tool_file.open('w') as f:
            json.dump(spec, f, indent=4)

        click.secho(
            f"✅ Successfully replaced '{data_store_type}' data store in tool '{tool_name}' with '{data_store_id}'.",
            fg="green")

    except (ValueError, KeyError, json.JSONDecodeError) as e:
        click.secho(f"Error processing tool file: {e}", fg="red")


@main.command()
@click.argument("source_dir",
                type=click.Path(exists=True,
                                file_okay=False,
                                dir_okay=True,
                                readable=True))
@click.argument("dest_dir",
                type=click.Path(file_okay=False, dir_okay=True, writable=True))
@click.argument("gcs_path")
@click.option("--upload",
              is_flag=True,
              help="If set, uploads generated files to GCS.")
def process_documents(source_dir: str, dest_dir: str, gcs_path: str,
                      upload: bool):
    """
    Preprocesses Markdown files for Data Store ingestion.

    Converts .md files to .html, extracts titles, generates a JSONL manifest,
    and optionally uploads them to a GCS bucket.

    GCS_PATH: The full GCS path (e.g., gs://my-bucket/my-docs/).

    Example:
        agentutil process-documents ./docs ./processed gs://my-bucket/my-docs/ --upload
    """
    source_path = Path(source_dir)
    dest_path = Path(dest_dir)
    dest_path.mkdir(exist_ok=True)
    click.echo(f"Source: {source_path}, Destination: {dest_path}")

    try:
        parsed_gcs_uri = urlparse(gcs_path)
        if parsed_gcs_uri.scheme != "gs":
            raise ValueError("GCS path must start with 'gs://'.")
        gcs_bucket_name = parsed_gcs_uri.netloc
        gcs_blob_prefix = parsed_gcs_uri.path.lstrip('/')
        if gcs_blob_prefix and not gcs_blob_prefix.endswith('/'):
            gcs_blob_prefix += '/'

        jsonl_entries = []
        files_to_upload = []
        markdown_files = list(source_path.glob("*.md"))

        if not markdown_files:
            click.secho(
                "Warning: No Markdown (.md) files found in source directory.",
                fg="yellow")
            return

        click.echo(
            f"Found {len(markdown_files)} Markdown files. Processing...")
        with click.progressbar(markdown_files,
                               label="Converting files") as bar:
            for md_file in bar:
                base_name = md_file.stem
                html_file = dest_path / f"{base_name}.html"

                md_content = md_file.read_text(encoding="utf-8")

                # Extract title from first H1, or use filename
                title = base_name
                for line in md_content.splitlines():
                    if line.strip().startswith("# "):
                        title = line.strip()[2:].strip()
                        break

                html_content = markdown.markdown(md_content)
                html_file.write_text(html_content, encoding="utf-8")
                files_to_upload.append(html_file)

                gcs_document_uri = f"gs://{gcs_bucket_name}/{gcs_blob_prefix}{html_file.name}"
                jsonl_entries.append({
                    "id": base_name,
                    "structData": {
                        "title": title
                    },
                    "content": {
                        "mimeType": "text/html",
                        "uri": gcs_document_uri
                    }
                })

        jsonl_path = dest_path / "documents.jsonl"
        with jsonl_path.open('w', encoding='utf-8') as f:
            for entry in jsonl_entries:
                f.write(json.dumps(entry) + '\n')
        files_to_upload.append(jsonl_path)
        click.echo(f"Generated JSONL manifest: {jsonl_path}")

        if upload:
            click.echo(
                f"\nUploading {len(files_to_upload)} files to gs://{gcs_bucket_name}/{gcs_blob_prefix}..."
            )
            storage_client = storage.Client()
            bucket = storage_client.bucket(gcs_bucket_name)

            with click.progressbar(files_to_upload,
                                   label="Uploading files") as bar:
                for local_file in bar:
                    blob_name = gcs_blob_prefix + local_file.name
                    blob = bucket.blob(blob_name)
                    blob.upload_from_filename(str(local_file))

        click.secho("\n✅ Preprocessing complete.", fg="green")

    except Exception as e:
        click.secho(f"\nAn error occurred: {e}", fg="red")


if __name__ == "__main__":
    main()
