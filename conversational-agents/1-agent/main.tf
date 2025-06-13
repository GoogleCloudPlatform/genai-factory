resource "google_storage_bucket" "build" {
  name                        = "${var.resource_id_prefix}config-${local.project_number}"
  location                    = var.agent_location
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_discovery_engine_data_store" "knowledge_base" {
  location          = var.agent_location
  data_store_id     = "${var.resource_id_prefix}knowledge-base"
  display_name      = "${var.resource_name_prefix}Knowledge Base"
  industry_vertical           = "GENERIC"
  content_config              = "CONTENT_REQUIRED"
  solution_types              = ["SOLUTION_TYPE_CHAT"]
  document_processing_config {
    default_parsing_config  {
      layout_parsing_config {}
    }
    chunking_config {
      layout_based_chunking_config {
        chunk_size = 500
        include_ancestor_headings = true
      }
    }
  }
  skip_default_schema_creation = true
}

resource "google_discovery_engine_schema" "knowledge_base" {
  location      = var.agent_location
  data_store_id = google_discovery_engine_data_store.knowledge_base.data_store_id
  schema_id     = "${var.resource_id_prefix}knowledge-base-schema"
  json_schema   = file("knowledge_base_data_store_schema.json")
}

resource "google_discovery_engine_data_store" "structured_faq" {
  location                    = var.agent_location
  data_store_id               = "${var.resource_id_prefix}structured-faq"
  display_name                = "${var.resource_name_prefix}Structured FAQ"
  industry_vertical           = "GENERIC"
  content_config              = "NO_CONTENT"
  solution_types              = ["SOLUTION_TYPE_CHAT"]
}

resource "google_discovery_engine_chat_engine" "agent" {
  engine_id = "${var.resource_id_prefix}agent"
  collection_id = "default_collection"
  location = var.agent_location
  display_name = "${var.resource_name_prefix}Agent"
  industry_vertical = "GENERIC"
  data_store_ids = [
    google_discovery_engine_data_store.knowledge_base.data_store_id,
    google_discovery_engine_data_store.structured_faq.data_store_id,
  ]
  chat_engine_config {
    agent_creation_config {
    default_language_code = var.agent_language
    time_zone = "Europe/Madrid"
    }
  }
}
