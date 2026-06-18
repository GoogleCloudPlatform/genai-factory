# Run these commands to complete the deployment.
# Alternatively, deploy the agent through your CI/CD pipeline.

# Get access token impersonating iac-rw SA
export IMPERSONATE_SERVICE_ACCOUNT="${service_account_emails["service-01/iac-rw"]}"

# Cleanup
rm -rf ./build

# Ingest data stores
%{ if length(datastores) > 0 ~}
echo "Ingesting Data Stores"
%{ for ds_id, ds_config in datastores ~}
echo "Ingesting Data Store: ${ds_id}..."

export DS_SOURCE_DIR=$(dirname "${ds_config.schema_path}")

mkdir -p ./build/data_store_${ds_id}
uv run scripts/agentutil.py data-store ingest \
  "$DS_SOURCE_DIR" \
  ./build/data_store_${ds_id} \
  ${bucket_url_build} \
  --ingest-to ${ds_config.name} \
  --impersonate-service-account "$IMPERSONATE_SERVICE_ACCOUNT"
%{ endfor ~}
%{ endif ~}

# Create and deploy agents
echo "Creating and Deploying Agents"
%{ for agent_id, agent_config in agents ~}
echo "Creating and Deploying Agent: ${agent_id}..."

# Rebuild agent
mkdir -p ./build/app/dist/${agent_id}
cp -r ./data/apps/default ./build/app/dist/${agent_id}/agent

# Update Data Store references
%{ for ds_name in agent_config.datastores ~}
uv run scripts/agentutil.py ces agent replace-data-store \
  "./build/app/dist/${agent_id}/agent" \
  "kb_data_store" \
  ${ds_name} \
  --impersonate-service-account "$IMPERSONATE_SERVICE_ACCOUNT"
%{ endfor ~}

%{ if length(toolsets) > 0 ~}
# Setup toolsets
%{ for k,v in toolsets ~}
uv run scripts/agentutil.py create-toolset \
  "./build/app/dist/${agent_id}/agent" \
  ${k} \
  ${v.uri} \
  --openapi-spec "${v.openapi_spec}" \%{ if try(length(v.allowed_ca_certs) > 0, false) }
  --allowed-ca-certs "${join(",", v.allowed_ca_certs)}" \%{ endif }%{ if try(v.service_directory, null) != null }
  --service-directory ${v.service_directory} \%{ endif }
  --impersonate-service-account "$IMPERSONATE_SERVICE_ACCOUNT"

%{ endfor ~}
%{ endif ~}

# Push the agent
uv run scripts/agentutil.py ces agent push ./build/app/dist/${agent_id}/agent/ \
  projects/${project_id}/locations/${region_discovery_engine}/apps/${agent_config.app_id} \
  ${bucket_url_build} \
  --impersonate-service-account "$IMPERSONATE_SERVICE_ACCOUNT"

# To finalize the agent configuration go to
# https://ces.cloud.google.com/projects/${project_id}/locations/${region_discovery_engine}/apps/${agent_config.app_id}

%{ endfor ~}
