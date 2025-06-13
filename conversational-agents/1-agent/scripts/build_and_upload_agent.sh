#!/bin/bash
set -e

export TARGET_AGENT_DIR='./build/agent/dist'

echo "Building Agent Variant: $AGENT_VARIANT"

mkdir -p ./build

# Make a copy of the agent in the target build directory
rm -rf $TARGET_AGENT_DIR
mkdir -p $TARGET_AGENT_DIR
cp -r ./agents/$AGENT_VARIANT/* $TARGET_AGENT_DIR

# Generate configuration from templates and Terraform outputs
agentutil replace_data_store $TARGET_AGENT_DIR "knowledge-base-and-faq" UNSTRUCTURED $KNOWLEDGE_BASE_DATA_STORE_NAME
# agentutil replace_data_store $TARGET_AGENT_DIR "knowledge-base-and-faq" STRUCTURED $FAQ_DATA_STORE_NAME

# Zip and upload agent
echo $(cd $TARGET_AGENT_DIR; zip -r agent.dist.zip *)

export TARGET_BUCKET_PATH="gs://${BUILD_BUCKET}/agents/agent-${AGENT_VARIANT}.dist.zip"
echo "Uploading agent to $TARGET_BUCKET_PATH"
gcloud storage cp $TARGET_AGENT_DIR/agent.dist.zip $TARGET_BUCKET_PATH

echo "Restoring Conversational Agent: $DIALOGFLOW_AGENT"
curl --request POST \
    --url https://${AGENT_LOCATION}-dialogflow.googleapis.com/v3/${DIALOGFLOW_AGENT}:restore \
    --header "Authorization: Bearer $(gcloud auth print-access-token)" \
    --header 'Content-Type: application/json' \
    --header "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
    --data "{
        \"agentUri\": \"$TARGET_BUCKET_PATH\"
    }"
    