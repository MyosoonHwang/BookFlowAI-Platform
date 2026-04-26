resource "google_vertex_ai_endpoint" "forecast" {
  name         = "bookflow-forecast-endpoint"
  display_name = "bookflow-forecast-endpoint"
  description  = "Private endpoint for BOOKFLOW demand forecasting inference."
  project      = var.project_id
  location     = local.region
  labels       = var.labels
  network      = data.google_compute_network.bookflow_vpc.id

  depends_on = [
    google_project_service.required["aiplatform.googleapis.com"],
  ]
}
