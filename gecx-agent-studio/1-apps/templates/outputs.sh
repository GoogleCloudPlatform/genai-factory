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
uv run agentutil data-store ingest \
  ./data/ds-kb \
  ./build/data_store \
  $bucket_url_ds \
  --ingest-to $ds_name

# Rebuild agent
mkdir -p ./build/app/dist
cp -r ../data/apps/default ./build/app/dist/agent

%{ for k,v in toolsets ~}
uv run agentutil create-toolset \
  "./build/app/dist/agent" \
  ${k} \
  ${v.uri}%{ if try(length(v.allowed_ca_certs) > 0, false) || try(v.service_directory, null) != null } \%{ endif }%{ if try(length(v.allowed_ca_certs) > 0, false) }
  --allowed-ca-certs ${v.allowed_ca_certs}%{ if try(v.service_directory, null) != null } \%{ endif }%{ endif }%{ if try(v.service_directory, null) != null }
  --service-directory ${v.service_directory}%{ endif }
%{ endfor ~}

uv run agentutil ces agent push ./build/app/dist/agent/ \
  projects/$project_id/locations/$region_discovery_engine/apps/$app_id \
  $bucket_url_build

# To finalize the agent configuration go to
# https://ces.cloud.google.com/projects/$project_id/locations/region_discovery_engine/apps/$app_id
