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

import logging
import json
import time
import shutil
import zipfile
import io
import os
from pathlib import Path
from typing import Optional

import requests
import google.auth
from google.auth.transport.requests import Request
from google.cloud import storage
from slugify import slugify

from agentutil.gcp_util import get_current_user_email, has_sa_user_role

logger = logging.getLogger(__name__)


class CesAgent:

    def __init__(self, local_agent_path: str):
        self.local_agent_path = Path(local_agent_path)
        self.credentials, self.project_id = google.auth.default()

    def _get_headers(self):
        if not self.credentials.valid:
            self.credentials.refresh(Request())
        return {
            "Authorization": f"Bearer {self.credentials.token}",
            "Content-Type": "application/json",
            "X-Goog-User-Project": self.project_id or "",
        }

    def replace_data_store(self, tool_name: str, data_store_id: str):
        """Replace a data store reference in environment.json.

        Args:
            tool_name: Name of the tool to update.
            data_store_id: ID (name) of the new data store.
        """
        env_path = self.local_agent_path / "environment.json"
        if not env_path.exists():
            raise FileNotFoundError(
                f"environment.json not found in {self.local_agent_path}")

        with open(env_path, "r") as f:
            data = json.load(f)

        # Path: .tools.<tool_name>.dataStoreTool.engineSource.dataStoreSources[0].dataStore.name
        try:
            # We verify the path exists before setting it to avoid creating garbage structure
            # if the tool doesn't exist or has different structure.
            tool_config = data.get("tools", {}).get(tool_name)
            if not tool_config:
                raise ValueError(
                    f"Tool '{tool_name}' not found in environment.json tools.")

            ds_tool = tool_config.get("dataStoreTool")
            if not ds_tool:
                raise ValueError(
                    f"Tool '{tool_name}' is not a Data Store tool (missing 'dataStoreTool')."
                )

            sources = ds_tool.get("engineSource",
                                  {}).get("dataStoreSources", [])
            if not sources:
                raise ValueError(
                    f"No dataStoreSources found in tool '{tool_name}'.")

            if len(sources) > 1:
                raise ValueError(
                    f"Tool '{tool_name}' has multiple data store sources. Only one is supported."
                )

            # Update the first source as per reference
            sources[0]["dataStore"]["name"] = data_store_id

            # Save back
            with open(env_path, "w") as f:
                json.dump(data, f, indent=4)

            logger.info(
                f"✅ Replaced Data Store reference in tool {tool_name} with: {data_store_id}"
            )

        except Exception as e:
            logger.error(f"❌ Failed to replace data store: {e}")
            raise

    def replace_sa_auth(self, tool_name: str, sa_email: str):
        """Replace Service Account authentication for a tool in environment.json.

        Args:
            tool_name: Name of the tool (e.g., 'cloud_logging').
            sa_email: Service Account email to use.
        """
        env_path = self.local_agent_path / "environment.json"
        if not env_path.exists():
            raise FileNotFoundError(
                f"environment.json not found in {self.local_agent_path}")

        with open(env_path, "r") as f:
            data = json.load(f)

        # Path: .toolsets.<tool_name>.openApiToolset.apiAuthentication.serviceAccountAuthConfig.serviceAccount
        try:
            toolsets = data.get("toolsets", {})
            toolset = toolsets.get(tool_name)
            if not toolset:
                raise ValueError(
                    f"Toolset '{tool_name}' not found in environment.json toolsets."
                )

            openapi = toolset.get("openApiToolset")
            if not openapi:
                # It might be a different kind of tool, but we are targeting OpenAPI auth
                raise ValueError(
                    f"Toolset '{tool_name}' does not appear to be an OpenAPI toolset."
                )

            auth_config = openapi.get("apiAuthentication",
                                      {}).get("serviceAccountAuthConfig")
            if not auth_config:
                raise ValueError(
                    f"serviceAccountAuthConfig not found for toolset '{tool_name}'."
                )

            auth_config["serviceAccount"] = sa_email

            with open(env_path, "w") as f:
                json.dump(data, f, indent=4)

            logger.info(
                f"✅ Updated Service Account for tool {tool_name} to: {sa_email}"
            )

        except Exception as e:
            logger.error(f"❌ Failed to update SA auth for {tool_name}: {e}")
            raise

    def _normalize_agent_id(self, agent_id: str) -> str:
        """Normalizes an agent ID or URL to a fully qualified agent resource name.

        Args:
            agent_id: Either a fully qualified agent ID (projects/*/locations/*/apps/*)
                     or a CES console URL (https://ces.cloud.google.com/projects/...).

        Returns:
            The normalized resource name.
        """
        if agent_id.startswith("http"):
            if "/projects/" in agent_id:
                # Extract path starting from projects/
                path = "projects/" + agent_id.split("/projects/", 1)[1]
                # Filter out query params or fragments
                path = path.split("?")[0].split("#")[0]
                # CES URLs might have extra components at the end (e.g. /versions)
                # We want up to the 6th component (projects/P/locations/L/apps/A)
                parts = path.split("/")
                if len(parts) >= 6:
                    agent_id = "/".join(parts[:6])
                else:
                    agent_id = path
        return agent_id

    def push(self, agent_id: str, bucket_name: str):
        """Push (upload and import) the local agent to the remote CES agent.

        Args:
             agent_id: Fully qualified agent resource name (projects/.../locations/.../apps/...)
                      or a CES console URL (https://ces.cloud.google.com/projects/...).
             bucket_name: GCS bucket name to use for intermediate storage.
        """
        agent_id = self._normalize_agent_id(agent_id)

        # 0. Permission Check
        self._check_sa_permissions()

        # 0.5 Validation
        app_json = self.local_agent_path / "app.json"
        app_yaml = self.local_agent_path / "app.yaml"
        if not app_json.exists() and not app_yaml.exists():
            raise ValueError(
                f"Invalid agent export: {self.local_agent_path} must contain app.json or app.yaml"
            )

        # 1. Zip
        logger.info(f"Zipping agent from {self.local_agent_path}")
        zip_buffer = io.BytesIO()
        with zipfile.ZipFile(zip_buffer, "w",
                             zipfile.ZIP_DEFLATED) as zip_file:
            for root, _, files in os.walk(self.local_agent_path):
                for file in files:
                    file_path = Path(root) / file
                    local_arcname = file_path.relative_to(
                        self.local_agent_path)
                    arcname = Path("agent") / local_arcname
                    zip_file.write(file_path, arcname)
        zip_buffer.seek(0)

        # 2. Upload to GCS

        blob_name = f"agentutil/push/{slugify(agent_id)}_{int(time.time())}.zip"
        gcs_uri = f"gs://{bucket_name}/{blob_name}"

        logger.info(f"Uploading to {gcs_uri}")
        storage_client = storage.Client(project=self.project_id,
                                        credentials=self.credentials)
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        blob.upload_from_file(zip_buffer)

        # 3. Import
        logger.info(f"Triggering import for {agent_id}")

        # Reference: https://ces.googleapis.com/v1beta/projects/$GCP_PROJECT_ID/locations/$CES_APP_LOCATION/apps:importApp

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
                "agent_id must be in format projects/.../locations/.../apps/..."
            )

        response = requests.post(url,
                                 headers=self._get_headers(),
                                 json=payload)
        if response.status_code != 200:
            raise RuntimeError(f"Import request failed: {response.text}")

        lro = response.json()
        op_name = lro.get("name")
        if not op_name:
            raise RuntimeError(f"No operation name in response: {lro}")

        try:
            op_result = self._poll_operation(op_name)

            # Check for warnings in the result response
            # Format: response.warnings[]
            response_data = op_result.get("response", {})
            warnings = response_data.get("warnings", [])
            if warnings:
                for warning in warnings:
                    logger.warning(f"⚠️ {warning}")

            logger.info("✅ Push completed successfully.")
        except Exception as e:
            logger.error(f"❌ Push failed: {e}")
            raise

    def pull(self,
             agent_id: str,
             bucket_name: str,
             environment_id: Optional[str] = None):
        """Pull (export) remote CES agent to local path.

        Args:
            agent_id: Fully qualified agent resource name or a CES console URL.
            bucket_name: GCS bucket name to use for intermediate storage.
            environment_id: Environment to export (not used currently as CES exportApp might not support it same way, or I need to check reference).
        """
        agent_id = self._normalize_agent_id(agent_id)

        # Create a unique blob name for export
        blob_name = f"agentutil/pull/{slugify(agent_id)}_{int(time.time())}.zip"
        gcs_uri = f"gs://{bucket_name}/{blob_name}"

        url = f"https://ces.googleapis.com/v1beta/{agent_id}:exportApp"
        payload = {"gcsUri": gcs_uri, "exportFormat": "JSON"}

        logger.info(f"Exporting agent {agent_id} to {gcs_uri}")
        response = requests.post(url,
                                 headers=self._get_headers(),
                                 json=payload)

        if response.status_code != 200:
            raise RuntimeError(f"Export request failed: {response.text}")

        lro = response.json()
        op_name = lro.get("name")
        if not op_name:
            raise RuntimeError(f"No operation name in response: {lro}")

        try:
            self._poll_operation(op_name)

            # Download
            logger.info("Downloading exported agent...")
            if self.local_agent_path.exists():
                shutil.rmtree(self.local_agent_path)
            self.local_agent_path.mkdir(parents=True, exist_ok=True)

            storage_client = storage.Client(project=self.project_id,
                                            credentials=self.credentials)
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(blob_name)

            zip_bytes = blob.download_as_bytes()

            # Unzip
            with zipfile.ZipFile(io.BytesIO(zip_bytes)) as z:
                # We look for a single top level directory
                top_level_dirs = {
                    item.split("/")[0]
                    for item in z.namelist() if "/" in item
                }

                if len(top_level_dirs) == 1:
                    # Extract to self.local_agent_path and if it puts it in subdir, move it up.
                    z.extractall(self.local_agent_path)

                    # Check if we have one subdir
                    params = [
                        p for p in self.local_agent_path.iterdir()
                        if p.is_dir()
                    ]
                    if len(params) == 1 and not any(
                            f.is_file()
                            for f in self.local_agent_path.iterdir()
                            if f.name != ".DS_Store"):
                        # Move everything up
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
            logger.warning(
                "No environment.json found. Skipping permission check.")
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

        # Check permission for each SA
        user_email = get_current_user_email(self.credentials)
        logger.info(
            f"Checking permissions for user {user_email} on SAs: {sas_to_check}"
        )

        for sa in sas_to_check:
            if not has_sa_user_role(sa, user_email, self.project_id,
                                    self.credentials):
                raise PermissionError(
                    f"User {user_email} does not have 'roles/iam.serviceAccountUser' on {sa} or project. Without this permission, the import operation will fail, as the service account is used to authenticate at least one OpenAPI tool in the app."
                )
