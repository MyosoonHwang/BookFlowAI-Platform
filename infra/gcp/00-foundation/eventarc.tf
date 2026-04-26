variable "eventarc_trigger_name" {
  description = "Name of the Eventarc trigger."
  type        = string
  default     = "bookflow-gcs-finalize-trigger"
}

variable "eventarc_source_bucket" {
  description = "Bucket name to watch for GCS object finalize events."
  type        = string
  default     = ""
}

variable "eventarc_workflow_name" {
  description = "Destination Workflows workflow name."
  type        = string
  default     = "bookflow-gcs-router"
}

resource "google_service_account" "eventarc_trigger" {
  account_id   = "bookflow-eventarc-trigger"
  project      = var.project_id
  display_name = "BOOKFLOW Eventarc Trigger"
}

resource "google_eventarc_trigger" "gcs_finalize" {
  name     = var.eventarc_trigger_name
  project  = var.project_id
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = var.eventarc_source_bucket != "" ? var.eventarc_source_bucket : google_storage_bucket.staging.name
  }

  destination {
    workflow = "projects/${var.project_id}/locations/${var.region}/workflows/${var.eventarc_workflow_name}"
  }

  service_account = google_service_account.eventarc_trigger.email

  depends_on = [
    google_project_service.required["eventarc.googleapis.com"],
    google_project_service.required["pubsub.googleapis.com"],
    google_project_service.required["workflows.googleapis.com"],
  ]
}
