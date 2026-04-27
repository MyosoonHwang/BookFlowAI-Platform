variable "project_id" {
  description = "GCP project ID for BOOKFLOW."
  type        = string
}

variable "project_name" {
  description = "Human-readable project name."
  type        = string
  default     = "BOOKFLOW v6.2"
}

variable "region" {
  description = "Primary GCP region."
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "Primary GCP zone."
  type        = string
  default     = "asia-northeast1-a"
}

variable "labels" {
  description = "Common labels applied to supported resources."
  type        = map(string)
  default = {
    project     = "bookflow"
    environment = "dev"
    owner       = "gcp"
    platform    = "multi-cloud"
  }
}

locals {
  required_services = toset([
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com",
    "compute.googleapis.com",
    "eventarc.googleapis.com",
    "iam.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "workflowexecutions.googleapis.com",
    "workflows.googleapis.com",
    "servicenetworking.googleapis.com",
  ])
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
