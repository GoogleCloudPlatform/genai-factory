# Run these commands to complete the deployment.
# Alternatively, deploy the agent through your CI/CD pipeline.

# Get access token impersonating iac-rw SA
export IMPERSONATE_SERVICE_ACCOUNT="${service_account_emails["service-01/iac-rw"]}"
export ACCESS_TOKEN=$(gcloud auth application-default print-access-token \
  --impersonate-service-account $IMPERSONATE_SERVICE_ACCOUNT)

# Cleanup
rm -rf ./build

# Build and ingest data store
mkdir -p ./build/data_store
uv run scripts/agentutil.py --impersonate-service-account "$IMPERSONATE_SERVICE_ACCOUNT" data-store ingest \
  ./data/ds-kb \
  ./build/data_store \
  ${bucket_url_ds} \
  --ingest-to ${ds_name}

# Rebuild agent
mkdir -p ./build/app/dist
cp -r ./data/apps/default ./build/app/dist/agent

# Update Data Store reference
uv run scripts/agentutil.py --impersonate-service-account "$IMPERSONATE_SERVICE_ACCOUNT" ces agent replace-data-store \
  "./build/app/dist/agent" \
  "kb_data_store" \
  ${ds_name}

%{ if length(toolsets) > 0 ~}
# Setup webhooks
%{ for k,v in toolsets ~}
uv run scripts/agentutil.py --impersonate-service-account "$IMPERSONATE_SERVICE_ACCOUNT" create-toolset \
  "./build/app/dist/agent" \
  ${k} \
  ${v.uri} \
  --openapi-spec "${v.openapi_spec}"%{ if try(length(v.allowed_ca_certs) > 0, false) || try(v.service_directory, null) != null } \%{ endif }%{ if try(length(v.allowed_ca_certs) > 0, false) }
  --allowed-ca-certs "${join(",", v.allowed_ca_certs)}"%{ if try(v.service_directory, null) != null } \%{ endif }%{ endif }%{ if try(v.service_directory, null) != null }
  --service-directory ${v.service_directory}%{ endif }

%{ endfor ~}
%{ endif ~}

# Push the agent
uv run scripts/agentutil.py --impersonate-service-account "$IMPERSONATE_SERVICE_ACCOUNT" ces agent push ./build/app/dist/agent/ \
  projects/${project_id}/locations/${region_discovery_engine}/apps/${app_id} \
  ${bucket_url_build}

# To finalize the agent configuration go to
# https://ces.cloud.google.com/projects/${project_id}/locations/${region_discovery_engine}/apps/${app_id}
