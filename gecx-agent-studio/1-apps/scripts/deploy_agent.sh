#!/bin/env bash

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

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

ENV_FILE="$SCRIPT_DIR/variables.generated.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Error: $ENV_FILE not found. Please run 'terraform apply' first."
    exit 1
fi

# Parse arguments
INGEST_KB=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ingest-kb) INGEST_KB=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

mkdir -p ./build

echo "Building Agent"

export TARGET_AGENT_DIR="./build/agent/dist"

# Make a copy of the agent in the target build directory
rm -rf $TARGET_AGENT_DIR
mkdir -p $TARGET_AGENT_DIR
cp -r ./apps/default $TARGET_AGENT_DIR/agent

# Update Data Store reference
agentutil ces agent replace-data-store $TARGET_AGENT_DIR/agent/ "kb_data_store" $KNOWLEDGE_BASE_DATA_STORE_NAME

# Zip and upload agent
echo "Uploading Agent"
agentutil ces agent push $TARGET_AGENT_DIR/agent/ projects/$GCP_PROJECT_ID/locations/$CES_APP_LOCATION/apps/$CES_APP_ID $BUILD_BUCKET

if [ "$INGEST_KB" = true ]; then
    echo "Ingesting Knowledge Base"
    export TARGET_KB_BUCKET_PATH="gs://$BUILD_BUCKET/$CES_APP_ID/data_store/ingestion/"
    agentutil data-store ingest ./data/knowledge-base ./build/data_store $TARGET_KB_BUCKET_PATH --ingest-to "$KNOWLEDGE_BASE_DATA_STORE_NAME"
fi
