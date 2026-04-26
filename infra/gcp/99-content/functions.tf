resource "google_cloudfunctions2_function" "content" {
  for_each = local.function_specs

  name        = each.value.name
  project     = var.project_id
  location    = var.region
  description = each.value.description
  labels      = var.labels

  build_config {
    runtime     = each.value.runtime
    entry_point = each.value.entry_point

    source {
      storage_source {
        bucket = local.function_source_bucket_name
        object = each.value.source
      }
    }
  }

  service_config {
    min_instance_count = each.value.min_instance
    max_instance_count = each.value.max_instance
    available_memory   = each.value.memory
    timeout_seconds    = each.value.timeout
    ingress_settings   = "ALLOW_INTERNAL_ONLY"
    service_account_email = {
      bq_load          = google_service_account.bq_load.email
      feature_assemble = google_service_account.feature_assemble.email
      vertex_invoke    = google_service_account.vertex_invoke.email
    }[each.key]
    vpc_connector                  = data.google_vpc_access_connector.bookflow.id
    vpc_connector_egress_settings  = "ALL_TRAFFIC"
    all_traffic_on_latest_revision = true
    environment_variables = merge(each.value.env, {
      BOOKFLOW_PROJECT_ID = var.project_id
    })
  }

  depends_on = [
    google_project_service.required["cloudfunctions.googleapis.com"],
    google_project_service.required["run.googleapis.com"],
    google_project_service.required["artifactregistry.googleapis.com"],
    google_project_service.required["cloudbuild.googleapis.com"],
    data.google_vpc_access_connector.bookflow,
  ]
}
