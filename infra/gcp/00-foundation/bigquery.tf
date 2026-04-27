resource "google_bigquery_dataset" "bookflow_dw" {
  project       = var.project_id
  dataset_id    = "bookflow_dw"
  friendly_name = "BOOKFLOW Data Warehouse"
  description   = "Analytics dataset for BOOKFLOW v6.2."
  location      = "asia-northeast1"
  # 1. 데이터셋 안의 테이블들을 한꺼번에 지울 수 있게 true로 변경
  delete_contents_on_destroy = true

  labels = var.labels

  depends_on = [
    google_project_service.required["bigquery.googleapis.com"],
  ]
}

resource "google_bigquery_table" "sales_fact" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.bookflow_dw.dataset_id
  table_id   = "sales_fact"
  # 2. 삭제 방지 옵션 해제
  deletion_protection = false

  schema = jsonencode([
    {
      name = "placeholder"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
}

resource "google_bigquery_table" "inventory" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.bookflow_dw.dataset_id
  table_id   = "inventory"
  # 2. 삭제 방지 옵션 해제
  deletion_protection = false

  schema = jsonencode([
    {
      name = "placeholder"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
}

resource "google_bigquery_table" "forecast_results" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.bookflow_dw.dataset_id
  table_id   = "forecast_results"
  # 2. 삭제 방지 옵션 해제
  deletion_protection = false

  schema = jsonencode([
    {
      name = "placeholder"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
}

resource "google_bigquery_table" "features" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.bookflow_dw.dataset_id
  table_id   = "features"

  deletion_protection = false

  schema = jsonencode([
    {
      name = "placeholder"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
}

resource "google_bigquery_table" "training_dataset" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.bookflow_dw.dataset_id
  table_id   = "training_dataset"

  deletion_protection = false

  schema = jsonencode([
    {
      name = "placeholder"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
}

resource "google_bigquery_table" "book_master" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.bookflow_dw.dataset_id
  table_id   = "book_master"

  deletion_protection = false

  schema = jsonencode([
    {
      name = "placeholder"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
}
