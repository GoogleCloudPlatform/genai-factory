#!/bin/bash
set -e

mkdir -p ./build

echo "📚 Importing FAQs"

export TARGET_FAQ_BUCKET_PATH="gs://$BUILD_BUCKET/data_store/cymbal_telecom_faq/faq.csv"

echo "Uploading FAQ CSV to: $TARGET_FAQ_BUCKET_PATH"
gcloud storage cp ./data_store/cymbal_telecom_faq/faq.csv $TARGET_FAQ_BUCKET_PATH

echo "Importing FAQs in Data Store: $FAQ_DATA_STORE_NAME"
curl --request POST \
--url https://${KNOWLEDGE_BASE_DATA_STORE_LOCATION}-discoveryengine.googleapis.com/v1/${FAQ_DATA_STORE_NAME}/branches/0/documents:import \
--header "Authorization: Bearer $(gcloud auth print-access-token)" \
--header 'Content-Type: application/json' \
--header "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
--data "{
    \"gcsSource\":{
        \"inputUris\":[\"${TARGET_FAQ_BUCKET_PATH}\"],
        \"dataSchema\":\"csv\"
    },
    \"reconciliationMode\":\"FULL\",
    \"autoGenerateIds\": true
}
"

echo "📚 Building Knowledge Base"

export TARGET_KB_BUCKET_PATH="gs://$BUILD_BUCKET/data_store/cymbal_telecom_kb/"
agentutil process_data_store_documents ./data_store/cymbal_telecom_kb/ ./build/data_store/cymbal_telecom_kb/ $TARGET_KB_BUCKET_PATH --upload

echo "Importing documents in Data Store: $KNOWLEDGE_BASE_DATA_STORE_NAME"
curl --request POST \
--url https://${KNOWLEDGE_BASE_DATA_STORE_LOCATION}-discoveryengine.googleapis.com/v1/${KNOWLEDGE_BASE_DATA_STORE_NAME}/branches/0/documents:import \
--header "Authorization: Bearer $(gcloud auth print-access-token)" \
--header 'Content-Type: application/json' \
--header "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
--data "{
    \"gcsSource\":{
        \"inputUris\":[\"${TARGET_KB_BUCKET_PATH}documents.jsonl\"],
        \"dataSchema\":\"document\"
    },
    \"reconciliationMode\":\"FULL\"
}
"

echo "🤖 Building Agent Variant: $AGENT_VARIANT"

export TARGET_AGENT_DIR='./build/agent/dist'

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
