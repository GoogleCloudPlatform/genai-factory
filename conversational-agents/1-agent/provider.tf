terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.35.0"
    }
  }
}

provider "google" {
  project               = var.gcp_project_id
  billing_project       = var.gcp_project_id
  user_project_override = true
}

data "google_project" "project_info" {
  project_id = var.gcp_project_id
}
