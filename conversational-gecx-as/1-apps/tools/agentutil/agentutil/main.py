import logging

import typer

from agentutil.ces.agent import CesAgent

logger = logging.getLogger(__name__)

app = typer.Typer(name='agentutil', help='A set of utilities to develop CX Agent Studio Apps.')

ces_app = typer.Typer()
app.add_typer(ces_app, name="ces", help="Utilities for CES platform")
ces_agent_app = typer.Typer()
ces_app.add_typer(ces_agent_app, name="agent", help="Manage CES agents")
documents_app = typer.Typer()
app.add_typer(documents_app, name="data-store", help="Process text documents and populate Data Stores.")

@ces_agent_app.command("replace-data-store")
def replace_data_store_ces(target_agent_dir: str, tool_name: str, data_store_id: str):
    """Replace a data store reference in a tool.
    
    Args:
        target_agent_dir: Path to local agent directory.
        tool_name: Name of the tool.
        data_store_id: ID of the new data store.
    """
    agent = CesAgent(target_agent_dir)
    agent.replace_data_store(tool_name, data_store_id)

@ces_agent_app.command()
def replace_sa_auth(target_agent_dir: str, tool_name: str, sa_email: str):
    """Replace Service Account authentication for a tool.
    
    Args:
        target_agent_dir: Path to local agent directory.
        tool_name: Name of the tool.
        sa_email: Service Account email.
    """
    agent = CesAgent(target_agent_dir)
    agent.replace_sa_auth(tool_name, sa_email)

@ces_agent_app.command()
def push(target_dir: str, agent_id: str, bucket: str):
    """Push local agent to remote CES agent.
    
    Args:
        target_dir: Path to local agent directory.
        agent_id: Remote Agent ID (resource name).
        bucket: GCS bucket name for intermediate storage.
    """
    agent = CesAgent(target_dir)
    agent.push(agent_id, bucket)

@ces_agent_app.command()
def pull(agent_id: str, target_dir: str, bucket: str, environment: str = None):
    """Pull remote CES agent to local directory.
    
    Args:
        agent_id: Remote Agent ID (resource name).
        target_dir: Local directory path.
        bucket: GCS bucket name for intermediate storage.
        environment: Optional environment ID.
    """
    agent = CesAgent(target_dir)
    agent.pull(agent_id, bucket, environment)

@documents_app.command('ingest')
def process_data_store_documents(
    source_dir: str,
    target_dir: str,
    gcs_bucket_folder_path: str,
    ingest_to: str = None
) -> None:
    """
    Preprocesses Markdown files for Data Store ingestion.

    Converts Markdown files to HTML, extracts titles, generates a JSONL manifest,
    and uploads the files to a GCS bucket.

    Args:
        source_dir: Path to the source folder containing Markdown (.md) files.
        target_dir: Path to the destination folder where HTML files
                                and the JSONL manifest will be placed.
        gcs_bucket_folder_path: Google Cloud Storage bucket folder path
                                (e.g., "gs://my-bucket/my/path/").
        ingest_to: Full resource name of the Data Store to ingest documents into.
                   If provided, triggers the import operation.

    Raises:
        FileNotFoundError: If the source folder does not exist.
        ValueError: If the GCS bucket path does not start with 'gs://'.
        Exception: For errors during GCS upload.
    """
    from agentutil.document_processing.data_store import process_data_store_documents
    process_data_store_documents(source_dir, target_dir, gcs_bucket_folder_path, ingest_to)

def main():
    app()

if __name__ == "__main__":
    main()
