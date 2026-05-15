"""Submit a Vertex AI AutoML Forecasting job for existing-book demand.

The training series is intentionally aggregated to ISBN + warehouse. Store-level
dashboard quantities are produced downstream by allocating warehouse forecasts
with recent store sales shares.
"""

import json
import os
from pathlib import Path

from google.cloud import aiplatform, bigquery


PROJECT = os.environ.get("BOOKFLOW_PROJECT_ID", "project-8ab6bf05-54d2-4f5d-b8d")
DATASET = os.environ.get("BOOKFLOW_BQ_DATASET", "bookflow_dw")
LOCATION = os.environ.get("BOOKFLOW_GCP_LOCATION", "asia-northeast1")

bq = bigquery.Client(project=PROJECT, location=LOCATION)
aiplatform.init(project=PROJECT, location=LOCATION)

print("[1/3] Creating warehouse-level AutoML forecast input view ...")
bq.query(
    f"""
    CREATE OR REPLACE VIEW `{PROJECT}.{DATASET}.v_automl_forecast_input` AS
    WITH date_spine AS (
      SELECT sale_date
      FROM UNNEST(GENERATE_DATE_ARRAY(
        (SELECT MIN(SAFE_CAST(sale_date AS DATE)) FROM `{PROJECT}.{DATASET}.sales_fact`),
        (SELECT MAX(SAFE_CAST(sale_date AS DATE)) FROM `{PROJECT}.{DATASET}.sales_fact`)
      )) AS sale_date
    ),
    series AS (
      SELECT DISTINCT
        s.isbn13,
        COALESCE(ls.wh_id, s.wh_id) AS wh_id
      FROM `{PROJECT}.{DATASET}.sales_fact` s
      LEFT JOIN `{PROJECT}.{DATASET}.store_location_map` slm
        ON slm.store_id = s.store_id
      LEFT JOIN `{PROJECT}.{DATASET}.locations_static` ls
        ON ls.location_id = slm.location_id
      WHERE s.sale_date IS NOT NULL
        AND COALESCE(ls.wh_id, s.wh_id) IS NOT NULL
    ),
    all_combinations AS (
      SELECT series.isbn13, series.wh_id, date_spine.sale_date
      FROM series
      CROSS JOIN date_spine
    ),
    daily_wh_sales AS (
      SELECT
        SAFE_CAST(s.sale_date AS DATE) AS sale_date,
        s.isbn13,
        COALESCE(ls.wh_id, s.wh_id) AS wh_id,
        SUM(COALESCE(CAST(s.qty_sold AS FLOAT64), 0)) AS qty_sold,
        SUM(COALESCE(CAST(s.revenue AS FLOAT64), 0)) AS revenue,
        AVG(COALESCE(CAST(s.avg_price AS FLOAT64), 0)) AS avg_price,
        SUM(COALESCE(CAST(s.tx_count AS FLOAT64), 0)) AS tx_count
      FROM `{PROJECT}.{DATASET}.sales_fact` s
      LEFT JOIN `{PROJECT}.{DATASET}.store_location_map` slm
        ON slm.store_id = s.store_id
      LEFT JOIN `{PROJECT}.{DATASET}.locations_static` ls
        ON ls.location_id = slm.location_id
      WHERE s.sale_date IS NOT NULL
      GROUP BY 1, 2, 3
    ),
    features_dedup AS (
      SELECT * EXCEPT(row_num)
      FROM (
        SELECT
          *,
          ROW_NUMBER() OVER (
            PARTITION BY isbn13, SAFE_CAST(feature_date AS DATE)
            ORDER BY SAFE_CAST(feature_date AS DATE)
          ) AS row_num
        FROM `{PROJECT}.{DATASET}.features`
      )
      WHERE row_num = 1
    )
    SELECT
      CONCAT(c.isbn13, '_WH', CAST(c.wh_id AS STRING)) AS series_id,
      c.sale_date,
      COALESCE(d.qty_sold, 0) AS qty_sold,
      COALESCE(d.revenue, 0) AS revenue,
      COALESCE(d.avg_price, 0) AS avg_price,
      COALESCE(d.tx_count, 0) AS tx_count,
      COALESCE(f.sns_mentions_1d, 0) AS sns_mentions_1d,
      COALESCE(f.sns_mentions_7d, 0) AS sns_mentions_7d,
      COALESCE(f.is_holiday, FALSE) AS is_holiday,
      COALESCE(f.event_nearby_days, 0) AS event_nearby_days,
      f.season,
      f.day_of_week,
      f.month,
      COALESCE(f.is_weekend, FALSE) AS is_weekend,
      c.wh_id,
      b.category_id,
      b.price_tier,
      CAST(COALESCE(b.is_bestseller_flag, FALSE) AS INT64) AS is_bestseller_flag,
      COALESCE(b.author_experience_years, 0) AS author_experience_years
    FROM all_combinations c
    LEFT JOIN daily_wh_sales d
      ON d.isbn13 = c.isbn13
     AND d.wh_id = c.wh_id
     AND d.sale_date = c.sale_date
    LEFT JOIN features_dedup f
      ON f.isbn13 = c.isbn13
     AND SAFE_CAST(f.feature_date AS DATE) = c.sale_date
    LEFT JOIN `{PROJECT}.{DATASET}.books_static` b
      ON b.isbn13 = c.isbn13
    """,
    location=LOCATION,
).result()
print("  done")

print("\n[2/3] Creating Vertex AI TimeSeriesDataset ...")
ts_dataset = aiplatform.TimeSeriesDataset.create(
    display_name="bookflow-sales-timeseries-wh",
    bq_source=f"bq://{PROJECT}.{DATASET}.v_automl_forecast_input",
)
print(f"  {ts_dataset.resource_name}")

print("\n[3/3] Submitting AutoML Forecasting job ...")
job = aiplatform.AutoMLForecastingTrainingJob(
    display_name="bookflow-sales-forecast-wh",
    optimization_objective="minimize-rmse",
    column_transformations=[
        {"timestamp": {"column_name": "sale_date"}},
        {"numeric": {"column_name": "qty_sold"}},
        {"numeric": {"column_name": "revenue"}},
        {"numeric": {"column_name": "avg_price"}},
        {"numeric": {"column_name": "tx_count"}},
        {"numeric": {"column_name": "sns_mentions_1d"}},
        {"numeric": {"column_name": "sns_mentions_7d"}},
        {"categorical": {"column_name": "is_holiday"}},
        {"numeric": {"column_name": "event_nearby_days"}},
        {"categorical": {"column_name": "season"}},
        {"numeric": {"column_name": "day_of_week"}},
        {"numeric": {"column_name": "month"}},
        {"categorical": {"column_name": "is_weekend"}},
        {"numeric": {"column_name": "wh_id"}},
        {"categorical": {"column_name": "category_id"}},
        {"categorical": {"column_name": "price_tier"}},
        {"numeric": {"column_name": "is_bestseller_flag"}},
        {"numeric": {"column_name": "author_experience_years"}},
    ],
)

model = job.run(
    dataset=ts_dataset,
    target_column="qty_sold",
    time_column="sale_date",
    time_series_identifier_column="series_id",
    time_series_attribute_columns=[
        "wh_id",
        "category_id",
        "price_tier",
        "is_bestseller_flag",
        "author_experience_years",
    ],
    available_at_forecast_columns=[
        "sale_date",
        "is_holiday",
        "event_nearby_days",
        "season",
        "day_of_week",
        "month",
        "is_weekend",
    ],
    unavailable_at_forecast_columns=[
        "qty_sold",
        "revenue",
        "avg_price",
        "tx_count",
        "sns_mentions_1d",
        "sns_mentions_7d",
    ],
    data_granularity_unit="day",
    data_granularity_count=1,
    forecast_horizon=5,
    context_window=28,
    budget_milli_node_hours=1000,
    model_display_name="bookflow-sales-forecast-wh",
    sync=True,
)

print("\nTraining complete")
print(f"  Model: {model.resource_name}")

state_file = Path(__file__).resolve().with_name("automl_job_state.json")
state_file.write_text(
    json.dumps(
        {
            "model_resource_name": model.resource_name,
            "dataset_resource_name": ts_dataset.resource_name,
        },
        indent=2,
    ),
    encoding="utf-8",
)
print(f"  State: {state_file}")
