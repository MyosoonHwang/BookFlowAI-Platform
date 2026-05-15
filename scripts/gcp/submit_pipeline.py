import os

from google.cloud import aiplatform


def require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


project_id = require_env("BOOKFLOW_GCP_PROJECT_ID")
project_number = os.getenv("BOOKFLOW_GCP_PROJECT_NUMBER", project_id)
location = require_env("BOOKFLOW_VERTEX_LOCATION")
dataset_id = require_env("BOOKFLOW_BQ_DATASET")
models_bucket = require_env("BOOKFLOW_MODELS_BUCKET")
staging_bucket = require_env("BOOKFLOW_STAGING_BUCKET")
pipeline_template_path = os.getenv(
    "BOOKFLOW_PIPELINE_TEMPLATE_PATH",
    f"gs://{models_bucket}/pipelines/bookflow-existing-books-pipeline.json",
)
pipeline_root = os.getenv(
    "BOOKFLOW_PIPELINE_ROOT",
    f"gs://{models_bucket}/pipeline-root",
)
service_account = require_env("BOOKFLOW_VERTEX_PIPELINE_SERVICE_ACCOUNT")

aiplatform.init(project=project_id, location=location)
job = aiplatform.PipelineJob(
    display_name=os.getenv(
        "BOOKFLOW_PIPELINE_DISPLAY_NAME",
        "bookflow-existing-books-forecast",
    ),
    template_path=pipeline_template_path,
    pipeline_root=pipeline_root,
    parameter_values={
        "project_id": project_id,
        "dataset_id": dataset_id,
        "bq_location": location,
        "sales_table": os.getenv("BOOKFLOW_SALES_TABLE", "sales_fact"),
        "inventory_table": os.getenv("BOOKFLOW_INVENTORY_TABLE", "inventory_daily"),
        "features_table": os.getenv("BOOKFLOW_FEATURES_TABLE", "features"),
        "books_table": os.getenv("BOOKFLOW_BOOKS_TABLE", "books_static"),
        "locations_table": os.getenv("BOOKFLOW_LOCATIONS_TABLE", "locations_static"),
        "store_location_map_table": os.getenv(
            "BOOKFLOW_STORE_LOCATION_MAP_TABLE",
            "store_location_map",
        ),
        "training_table": os.getenv("BOOKFLOW_TRAINING_TABLE", "training_dataset"),
        "validation_table": os.getenv(
            "BOOKFLOW_TRAINING_VALIDATION_TABLE",
            "training_validation_log",
        ),
        "baseline_table": os.getenv(
            "BOOKFLOW_BASELINE_TABLE",
            "forecast_baseline_metrics",
        ),
        "model_name": os.getenv(
            "BOOKFLOW_BQML_MODEL_NAME",
            "bookflow_existing_books_forecast",
        ),
        "forecast_table": os.getenv("BOOKFLOW_FORECAST_TABLE", "forecast_results"),
        "staging_bucket": staging_bucket,
        "models_bucket": models_bucket,
        "source_object": require_env("BOOKFLOW_SOURCE_OBJECT"),
        "business_timezone": os.getenv("BOOKFLOW_BUSINESS_TIMEZONE", "Asia/Seoul"),
        "max_data_lag_days": int(os.getenv("BOOKFLOW_MAX_DATA_LAG_DAYS", "1")),
        "min_training_rows": int(os.getenv("BOOKFLOW_MIN_TRAINING_ROWS", "1000000")),
        "min_time_series_count": int(os.getenv("BOOKFLOW_MIN_TIME_SERIES_COUNT", "1000")),
        "max_required_null_ratio": float(
            os.getenv("BOOKFLOW_MAX_REQUIRED_NULL_RATIO", "0.01")
        ),
        "max_zero_sales_ratio": float(os.getenv("BOOKFLOW_MAX_ZERO_SALES_RATIO", "0.95")),
        "baseline_holdout_days": int(os.getenv("BOOKFLOW_BASELINE_HOLDOUT_DAYS", "28")),
    },
)
job.submit(service_account=service_account)
print("Pipeline job submitted:", job.resource_name)
print("State:", job.state)
print(
    "Console:",
    "https://console.cloud.google.com/vertex-ai/locations/"
    f"{location}/pipelines/runs/{job.resource_name.split('/')[-1]}"
    f"?project={project_number}",
)
