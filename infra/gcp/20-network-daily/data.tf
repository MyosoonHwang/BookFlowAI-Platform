variable "project_id" {
  description = "GCP project ID for BOOKFLOW."
  type        = string
}

variable "region" {
  description = "Primary GCP region."
  type        = string
  default     = "asia-northeast1"
}

data "google_compute_network" "bookflow_vpc" {
  name    = "bookflow-vpc"
  project = var.project_id
}
