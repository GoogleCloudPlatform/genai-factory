"""
Patches elements of a given exported agent to match the deployment configuration.
"""
import json
import io
import zipfile
import os
import logging
import datetime
import shutil
from enum import Enum

import fire
import markdown
from google.cloud import dialogflowcx_v3beta1 as dialogflow
from google.cloud import storage

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

AGENTUTIL_FOLDER = '.agentutil'
AGENT_BACKUP_FOLDER = os.path.join(AGENTUTIL_FOLDER,'agent_backups')

class DataStoreType(Enum):
    STRUCTURED='STRUCTURED'
    UNSTRUCTURED='UNSTRUCTURED'
    PUBLIC_WEB='PUBLIC_WEB'

class ConversationalAgentsUtils(object):
    """A set of utilities to manipulate Conversational Agents."""

    def __init__(self):
        if not os.path.exists(AGENTUTIL_FOLDER):
            os.makedirs(AGENTUTIL_FOLDER)
        if not os.path.exists(AGENT_BACKUP_FOLDER):
            os.makedirs(AGENT_BACKUP_FOLDER)
        self.client = dialogflow.AgentsClient()

    def replace_data_store(self, target_agent_dir: str, data_store_tool_name: str, data_store_type: DataStoreType, data_store_id: str):
        """Replace a data store reference in a tool. Will modify the given agent in place.
        
        Args:
            target_agent_dir: Path to a directory that contains the exported Conversational Agent to update.
            data_store_tool_name: Name of the tool to update.
            data_store_type: Type of the data store to replace.
            data_store_id: ID of the new data store.
        """

        with open(os.path.join(target_agent_dir, 'tools', data_store_tool_name, f'{data_store_tool_name}.json'), 'r') as f:
            ds_spec = json.load(f)

        if len(ds_spec['dataStoreSpec']['dataStoreConnections']) == 0:
            raise ValueError(f"Exported agent has no Data Store connections in tool {data_store_tool_name}. Can't map {data_store_type} Data Store: {data_store_id}")
        
        done = False
        for connection in ds_spec['dataStoreSpec']['dataStoreConnections']:
            if connection['dataStoreType'] == data_store_type:
                connection['dataStore'] = data_store_id
                done = True
        if not done:
            raise ValueError(f"Couldn't find a Data Store connection of type {data_store_type} in tool {data_store_tool_name}. Can't map Data Store: {data_store_id}")

        with open(os.path.join(target_agent_dir, 'tools', data_store_tool_name, f'{data_store_tool_name}.json'), 'w') as f:
            json.dump(ds_spec, f, indent=4)

        print(f"Replaced {data_store_type} Data Store reference in tool {data_store_tool_name} with: {data_store_id}.")

    def pull_agent(self, agent_name: str, target_dir: str, environment: str=None):
        """Exports a Dialogflow CX agent to a local folder.

        Example usage:
            $ agentutil export_agent projects/<PROJECT>/locations/europe-west1/agents/<AGENT-ID> my-local-dir/

        Args:
            agent_name: Fully qualified name of the agent to export, e.g. projects/<PROJECT_ID>/locations/<LOCATION_ID>/agents/<AGENT_ID>
            target_dir: Local directory where the agent will be exported.
            environment: Environment to export. If not specified, the draft environment is exported.
        """
        target_dir = target_dir.rstrip('/')
        agent_name = agent_name.rstrip('/')
        environment = f"{agent_name}/environments/{environment}" if environment else None

        # Make export request
        client = self._get_client(agent_name)
        logger.info(f"Exporting agent: {agent_name}")
        request = dialogflow.ExportAgentRequest(
            name=agent_name,
            data_format=dialogflow.ExportAgentRequest.DataFormat.JSON_PACKAGE,
            environment=environment
        )
        operation = client.export_agent(request=request)
        response: dialogflow.ExportAgentResponse = operation.result() # type: ignore

        # Write exported ZIP
        if response.agent_content:
            # Backup current version
            if os.path.exists(target_dir):
                now = datetime.datetime.now()
                backup_dir = os.path.join(AGENT_BACKUP_FOLDER, os.path.basename(target_dir))
                shutil.rmtree(backup_dir, ignore_errors=True)
                shutil.copytree(target_dir, backup_dir)
                logger.info(f"Created backup of agent in: {backup_dir}")
            else:
                logger.warning(f"Target directory does not exist, will be created: {target_dir}")
                os.makedirs(target_dir)

            # Replace with exported agent
            shutil.rmtree(target_dir, ignore_errors=True)
            with zipfile.ZipFile(io.BytesIO(response.agent_content), 'r') as zip_ref:
                zip_ref.extractall(target_dir)
            print(f"CX Agent pulled successfully to local dir: {target_dir}")
        elif response.agent_uri:
            print(f"CX Agent exported to Google Cloud Storage at: {response.agent_uri}")
            print("You'll need to download it from GCS separately.")
        else:
            print("No CX agent content or URI returned. Export might have failed or returned empty.")

    def process_data_store_documents(
        self,
        source_folder_path: str,
        destination_folder_path: str,
        gcs_bucket_folder_path: str,
        upload: bool = False
    ) -> None:
        """
        Preprocesses Markdown files for Data Store ingestion.

        Converts Markdown files to HTML, extracts titles, generates a JSONL manifest,
        and optionally uploads the files to a GCS bucket.

        Args:
            source_folder_path: Path to the source folder containing Markdown (.md) files.
            destination_folder_path: Path to the destination folder where HTML files
                                    and the JSONL manifest will be placed.
            gcs_bucket_folder_path: Google Cloud Storage bucket folder path
                                    (e.g., "gs://my-bucket/my/path/").
            upload: If True, upload generated HTML files and the JSONL manifest
                    to the specified GCS bucket path. Defaults to False.

        Raises:
            FileNotFoundError: If the source folder does not exist.
            ValueError: If the GCS bucket path does not start with 'gs://'.
            Exception: For errors during GCS upload.
        """

        # --- 1. Input Validation and Setup ---
        if not os.path.isdir(source_folder_path):
            raise FileNotFoundError(f"Error: Source folder not found: '{source_folder_path}'")

        os.makedirs(destination_folder_path, exist_ok=True)
        print(f"Destination folder ensured: '{destination_folder_path}'")

        if not gcs_bucket_folder_path.startswith("gs://"):
            raise ValueError(f"Error: GCS bucket path must start with 'gs://'. Got: '{gcs_bucket_folder_path}'")
        
        # Parse GCS path into bucket name and blob prefix
        # Example: "gs://my-bucket/my/path/" -> bucket="my-bucket", prefix="my/path/"
        # Example: "gs://my-bucket/" -> bucket="my-bucket", prefix=""
        gcs_path_components = gcs_bucket_folder_path[len("gs://"):].split('/', 1)
        gcs_bucket_name = gcs_path_components[0]
        gcs_blob_prefix = gcs_path_components[1] if len(gcs_path_components) > 1 else ""
        
        # Ensure blob prefix ends with a slash if it's not empty, indicating a folder path
        if gcs_blob_prefix and not gcs_blob_prefix.endswith('/'):
            gcs_blob_prefix += '/'

        print(f"Parsed GCS path: Bucket='{gcs_bucket_name}', Blob Prefix='{gcs_blob_prefix}'")

        jsonl_entries = []
        local_files_to_upload = [] # List to keep track of local file paths that need to be uploaded

        # --- 2. Process Markdown Files ---
        print("\nStarting Markdown file processing...")
        markdown_files_found = False
        for filename in os.listdir(source_folder_path):
            if not filename.endswith(".md"):
                continue

            markdown_files_found = True
            md_filepath = os.path.join(source_folder_path, filename)
            base_name = os.path.splitext(filename)[0] # filename without .md extension
            html_filename = f"{base_name}.html"
            html_filepath = os.path.join(destination_folder_path, html_filename)

            print(f"  Processing '{filename}'...")

            try:
                with open(md_filepath, 'r', encoding='utf-8') as f:
                    md_content = f.read()

                # Extract title: First level title (#) or basename if not present
                title = base_name # Default title
                lines = md_content.split('\n')
                for line in lines:
                    stripped_line = line.strip()
                    if stripped_line.startswith('# '):
                        title = stripped_line[2:].strip() # Remove '# ' and whitespace
                        break # Found the first H1, use it and exit loop

                # Convert Markdown to HTML
                html_content = markdown.markdown(md_content)

                # Save HTML file to destination folder
                with open(html_filepath, 'w', encoding='utf-8') as f:
                    f.write(html_content)
                print(f"    - Converted to HTML and saved: '{html_filepath}'")
                local_files_to_upload.append(html_filepath)

                # Prepare JSONL entry
                # The URI for Discovery Engine must point to the *final GCS location*
                gcs_document_uri = f"{gcs_bucket_folder_path}{html_filename}"
                
                jsonl_entry = {
                    "id": base_name,
                    "structData": {"title": title},
                    "content": {
                        "mimeType": "text/html",
                        "uri": gcs_document_uri
                    }
                }
                jsonl_entries.append(jsonl_entry)
                print(f"    - Prepared JSONL entry for ID: '{base_name}' (Title: '{title}')")

            except Exception as e:
                print(f"  Error processing '{filename}': {e}")
                # Continue to the next file if an error occurs with one file
                continue 
        
        if not markdown_files_found:
            print("No Markdown files (.md) found in the source folder.")

        # --- 3. Generate JSONL Manifest ---
        jsonl_output_filename = "documents.jsonl"
        jsonl_output_path = os.path.join(destination_folder_path, jsonl_output_filename)
        
        with open(jsonl_output_path, 'w', encoding='utf-8') as f:
            for entry in jsonl_entries:
                f.write(json.dumps(entry) + '\n')
        print(f"\nGenerated JSONL manifest: '{jsonl_output_path}' with {len(jsonl_entries)} entries.")
        local_files_to_upload.append(jsonl_output_path) # Add JSONL itself to upload list

        # --- 4. Upload to GCS (if upload flag is True) ---
        if upload:
            print(f"\nUploading generated files to GCS bucket: '{gcs_bucket_folder_path}'...")
            try:
                storage_client = storage.Client()
                bucket = storage_client.bucket(gcs_bucket_name)

                for local_file_path in local_files_to_upload:
                    # Construct the blob path in GCS
                    # Example: /tmp/dest/doc1.html -> doc1.html
                    # Example: /tmp/dest/documents.jsonl -> documents.jsonl
                    relative_path_from_dest = os.path.relpath(local_file_path, destination_folder_path)
                    gcs_blob_name = gcs_blob_prefix + relative_path_from_dest

                    blob = bucket.blob(gcs_blob_name)
                    blob.upload_from_filename(local_file_path)
                    print(f"  Uploaded '{local_file_path}' to 'gs://{gcs_bucket_name}/{gcs_blob_name}'")

            except Exception as e:
                print(f"Error during GCS upload: {e}")
                # Re-raise the exception to indicate a critical failure during upload
                raise 

        print("\nPreprocessing complete.")

    def _get_client(self, agent_name: str):
        location_id = agent_name.split('/')[3]
        client_options = {"api_endpoint": f"{location_id}-dialogflow.googleapis.com"}
        return dialogflow.AgentsClient(client_options=client_options)

def main():
    fire.Fire(ConversationalAgentsUtils)

if __name__ == "__main__":
    main()
