output "commands" {
  description = "Run the following commands when the deployment completes to deploy the app."
  value       = <<EOT
  # Run the following commands to deploy the application.
  # Alternatively, deploy the agent through your CI/CD pipeline.

  source variables.generated.env
  uv run scripts/build_and_upload_agent.sh
  EOT
}

resource "local_file" "env_vars" {
  content = <<-EOT
export GCP_PROJECT_ID="${var.gcp_project_id}"
export AGENT_VARIANT="${var.agent_variant}"
export AGENT_REMOTE="${var.agent_remote}"
export AGENT_LOCATION="${element(split("/", google_discovery_engine_chat_engine.agent.chat_engine_metadata[0].dialogflow_agent), 3)}"
export BUILD_BUCKET="${google_storage_bucket.build.name}"
export KNOWLEDGE_BASE_DATA_STORE_LOCATION="${google_discovery_engine_data_store.knowledge_base.location}"
export KNOWLEDGE_BASE_DATA_STORE_ID="${google_discovery_engine_data_store.knowledge_base.data_store_id}"
export KNOWLEDGE_BASE_DATA_STORE_NAME="${google_discovery_engine_data_store.knowledge_base.name}"
export FAQ_DATA_STORE_NAME="${google_discovery_engine_data_store.structured_faq.name}"
export AGENT_ID="${google_discovery_engine_chat_engine.agent.engine_id}"
export AGENT_NAME="${google_discovery_engine_chat_engine.agent.name}"
export DIALOGFLOW_AGENT="${google_discovery_engine_chat_engine.agent.chat_engine_metadata[0].dialogflow_agent}"
EOT
  filename = "${path.module}/variables.generated.env"
}
