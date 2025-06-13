variable "gcp_project_id" {
  description = "The project where to deploy Conversational Agents"
  type        = string
}

variable "agent_variant" {
  description = "An Agent ID, will be used to reference resources such as the stored agent export"
  type        = string
}

variable "agent_location" {
  description = "The region where to deploy Agent and Data Stores"
  type        = string
}

variable "agent_language" {
  description = "Default language for the agent"
  type        = string
}

variable "agent_remote" {
  description = "A separate remote agent that is meant to be consistent with the one deployed by this project. This value is not used for deployment, but will be accessed by script to sync remote content."
  type        = string
}

variable "resource_id_prefix" {
  description = "A prefix that will be added to deployed resource IDs"
  type        = string
}

variable "resource_name_prefix" {
  description = "A prefix that will be added to deployed resource names"
  type        = string
}
