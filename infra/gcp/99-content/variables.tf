variable "project_id" {
  description = "GCP project ID for BOOKFLOW content pipeline."
  type        = string
}

variable "region" {
  description = "Primary GCP region for content services."
  type        = string
  default     = "asia-northeast1"
}

variable "bigquery_location" {
  description = "BigQuery dataset location."
  type        = string
  default     = "asia-northeast1"
}

variable "labels" {
  description = "Common labels applied to supported resources."
  type        = map(string)
  default = {
    project     = "bookflow"
    environment = "dev"
    owner       = "gcp"
    workload    = "content"
  }
}

variable "vpc_connector_name" {
  description = "Existing Serverless VPC Access connector name attached to bookflow-vpc."
  type        = string
  default     = "bookflow-vpc-connector"
}

variable "vpc_name" {
  description = "Existing BOOKFLOW VPC name."
  type        = string
  default     = "bookflow-vpc"
}

variable "dataset_id" {
  description = "BigQuery dataset id."
  type        = string
  default     = "bookflow_dw"
}

variable "staging_bucket_name" {
  description = "Existing GCS staging bucket name. Defaults to the foundation naming convention."
  type        = string
  default     = null
}

variable "models_bucket_name" {
  description = "Existing GCS models bucket name. Defaults to the foundation naming convention."
  type        = string
  default     = null
}

variable "function_source_bucket_name" {
  description = "Bucket containing zipped Cloud Function source archives. Defaults to the staging bucket."
  type        = string
  default     = null
}

variable "function_source_objects" {
  description = "Zipped source object names for each Cloud Function."
  type = object({
    bq_load          = string
    feature_assemble = string
    vertex_invoke    = string
  })
  default = {
    bq_load          = "functions/bookflow-bq-load.zip"
    feature_assemble = "functions/bookflow-feature-assemble.zip"
    vertex_invoke    = "functions/bookflow-vertex-invoke.zip"
  }
}

variable "vertex_pipeline_template_uri" {
  description = "Vertex AI Pipeline template URI used for existing-book training and batch prediction."
  type        = string
  default     = null
}

variable "vertex_pipeline_root" {
  description = "Vertex AI Pipeline root path."
  type        = string
  default     = null
}

variable "function_max_instance_count" {
  description = "Default max instances for Cloud Functions."
  type        = number
  default     = 5
}
