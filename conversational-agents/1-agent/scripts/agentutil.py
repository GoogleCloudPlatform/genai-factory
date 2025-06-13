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
from google.cloud import dialogflowcx_v3beta1 as dialogflow

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
        response = operation.result()

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

    def _get_client(self, agent_name: str):
        location_id = agent_name.split('/')[3]
        client_options = {"api_endpoint": f"{location_id}-dialogflow.googleapis.com"}
        return dialogflow.AgentsClient(client_options=client_options)

def main():
    fire.Fire(ConversationalAgentsUtils)

if __name__ == "__main__":
    main()
