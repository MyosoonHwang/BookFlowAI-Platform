data "google_compute_network" "bookflow_vpc" {
  name    = var.vpc_name
  project = var.project_id
}

data "google_vpc_access_connector" "bookflow" {
  name    = var.vpc_connector_name
  project = var.project_id
  region  = var.region
}

data "google_storage_bucket" "staging" {
  name = local.staging_bucket_name
}

data "google_storage_bucket" "models" {
  name = local.models_bucket_name
}

data "google_bigquery_dataset" "bookflow_dw" {
  project    = var.project_id
  dataset_id = var.dataset_id
}

data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}
