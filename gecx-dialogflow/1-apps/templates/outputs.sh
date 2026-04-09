# Run these commands to complete the deployment.
# Alternatively, deploy the agent through your CI/CD pipeline.

# Get bearer token impersonating iac-rw SA
export BEARER_TOKEN=$(gcloud auth print-access-token \
  --impersonate-service-account ${service_accounts["project/iac-rw"].email})

# Load faq data into the data store
gcloud storage cp ./data/ds-faq/faq.csv ${bucket_url_ds}/ds-faq/ \
  --impersonate-service-account ${service_accounts["project/iac-rw"].email} \
  --billing-project ${project_id} &&
curl -X POST ${ds_uri_faq} \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${project_id}" \
  -d '{
      "autoGenerateIds": true,
      "gcsSource":{
        "inputUris":["${bucket_url_ds}/ds-faq/faq.csv"],
        "dataSchema":"csv"
      },
      "reconciliationMode":"FULL"
    }'

# Load kb data into the data store
uv run ./scripts/agentutil.py process-documents \
  ./data/ds-kb/ \
  ./build/data/ds-kb/ \
  ${bucket_url_ds}/ds-kb/ \
  --upload &&
curl -X POST ${ds_uri_kb} \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${project_id}" \
  -d '{
      "gcsSource":{
        "inputUris":["${bucket_url_ds}/ds-kb/documents.jsonl"],
        "dataSchema":"document"
      },
      "reconciliationMode":"FULL"
    }'

# Build and deploy an agent variant
rm -rf ${agent_dir} &&
mkdir -p ${agent_dir} &&
cp -r ./data/agents/${agent_variant}/* ${agent_dir} &&
uv run ./scripts/agentutil.py replace-data-store \
  "${agent_dir}" \
  "knowledge-base-and-faq" \
  UNSTRUCTURED \
  "${ds_name_kb}" &&
uv run ./scripts/agentutil.py replace-data-store \
  "./build/agent/dist" \
  "knowledge-base-and-faq" \
  STRUCTURED \
  "${ds_name_faq}" &&
zip -r ${agent_dir}/agent.dist.zip ${agent_dir}/* &&
gcloud storage cp ${agent_dir}/agent.dist.zip ${bucket_url_build}/agents/agent-${agent_variant}.dist.zip \
  --impersonate-service-account ${service_accounts["project/iac-rw"].email} \
  --billing-project ${project_id} &&
curl -X POST ${agent_uri} \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${project_id}" \
  -d '{
      "agentUri": "${bucket_url_build}/agents/agent-${agent_variant}.dist.zip"
    }'


%{ for k,v in webhooks ~}
uv run ./scripts/agentutil.py create-webhook \
  ${agent_dir} \
  ${k} \
  ${v.uri}%{ if try(length(v.allowed_ca_certs) > 0, false) || try(v.service_directory, null) != null } \%{ endif }%{ if try(length(v.allowed_ca_certs) > 0, false) }
  --allowed-ca-certs ${v.allowed_ca_certs}%{ if try(v.service_directory, null) != null } \%{ endif }%{ endif }%{ if try(v.service_directory, null) != null }
  --service-directory ${v.service_directory}%{ endif }
%{ endfor ~}

# Query the agent
curl -X POST ${agent_uri_query} \
-H "Authorization: Bearer $BEARER_TOKEN" \
-H "Content-Type: application/json" \
-H "X-Goog-User-Project: ${project_id}" \
-d '{
      "query_input": {
        "language_code": "${agent_language}",
        "text": {
          "text": "Hello, bot"
        }
      }
    }'

# To finalize the agent configuration go to
# https://conversational-agents.cloud.google.com/projects/${project_id}/locations/${agent_region}/agents
