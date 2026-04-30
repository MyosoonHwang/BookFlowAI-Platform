locals {
  required_services = toset([
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "compute.googleapis.com",
    "eventarc.googleapis.com",
    "iam.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "vpcaccess.googleapis.com",
    "workflowexecutions.googleapis.com",
    "workflows.googleapis.com",
  ])

  region             = var.region
  vpc_name           = var.vpc_name
  vpc_connector_name = var.vpc_connector_name
  dataset_id         = var.dataset_id

  staging_bucket_name          = coalesce(var.staging_bucket_name, "${var.project_id}-bookflow-staging")
  models_bucket_name           = coalesce(var.models_bucket_name, "${var.project_id}-bookflow-models")
  function_source_bucket_name  = coalesce(var.function_source_bucket_name, local.staging_bucket_name)
  vertex_pipeline_template_uri = coalesce(var.vertex_pipeline_template_uri, "gs://${var.project_id}-bookflow-models/pipelines/bookflow-existing-books-pipeline.json")
  vertex_pipeline_root         = coalesce(var.vertex_pipeline_root, "gs://${var.project_id}-bookflow-models/pipeline-root")

  function_specs = {
    bq_load = {
      name         = "bookflow-bq-load"
      description  = "Loads finalized GCS staging objects into BigQuery tables."
      entry_point  = "handler"
      runtime      = "python312"
      memory       = "512M"
      timeout      = 540
      min_instance = 0
      max_instance = 3
      source       = var.function_source_objects.bq_load
      env = {
        BOOKFLOW_DATASET_ID        = var.dataset_id
        BOOKFLOW_BQ_LOCATION       = var.bigquery_location
        BOOKFLOW_STAGING_BUCKET    = local.staging_bucket_name
        BOOKFLOW_LOAD_TABLES       = "sales_fact,inventory_daily,features,books_static,locations_static"
        BOOKFLOW_WRITE_DISPOSITION = "WRITE_APPEND"
      }
    }
    feature_assemble = {
      name         = "bookflow-feature-assemble"
      description  = "Assembles new-book inference features from BigQuery."
      entry_point  = "handler"
      runtime      = "python312"
      memory       = "512M"
      timeout      = 540
      min_instance = 0
      max_instance = 3
      source       = var.function_source_objects.feature_assemble
      env = {
        BOOKFLOW_DATASET_ID     = var.dataset_id
        BOOKFLOW_BQ_LOCATION    = var.bigquery_location
        BOOKFLOW_FEATURE_TABLES = "sales_fact,books_static,features"
      }
    }
    vertex_invoke = {
      name         = "bookflow-vertex-invoke"
      description  = "Invokes the existing Vertex AI private endpoint for new-book inference."
      entry_point  = "handler"
      runtime      = "python312"
      memory       = "1024M"
      timeout      = 540
      min_instance = 0
      max_instance = var.function_max_instance_count
      source       = var.function_source_objects.vertex_invoke
      env = {
        BOOKFLOW_VERTEX_ENDPOINT = google_vertex_ai_endpoint.forecast.name
        BOOKFLOW_VERTEX_LOCATION = local.region
        BOOKFLOW_DATASET_ID      = var.dataset_id
      }
    }
  }
}
