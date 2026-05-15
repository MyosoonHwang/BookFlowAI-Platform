"""Compile the BOOKFLOW existing-books Vertex AI Pipeline as a KFP v2 spec.

All deployment-specific values are provided by CLI flags or environment
variables. The script intentionally avoids embedding project IDs, bucket names,
or dataset names in the pipeline definition.
"""

import argparse
import os
from pathlib import Path

from kfp import compiler, dsl


ENV_OUTPUT_JSON = "BOOKFLOW_PIPELINE_JSON"


@dsl.component(base_image="python:3.12-slim")
def validate_runtime_config(
    project_id: str,
    dataset_id: str,
    staging_bucket: str,
    models_bucket: str,
    source_object: str,
) -> str:
    values = {
        "project_id": project_id,
        "dataset_id": dataset_id,
        "staging_bucket": staging_bucket,
        "models_bucket": models_bucket,
        "source_object": source_object,
    }
    missing = [name for name, value in values.items() if not value]
    if missing:
        raise ValueError(f"Missing required pipeline values: {', '.join(missing)}")
    return models_bucket


@dsl.component(
    base_image="python:3.12-slim",
    packages_to_install=["google-cloud-bigquery"],
)
def build_training_dataset(
    project_id: str,
    dataset_id: str,
    sales_table: str,
    inventory_table: str,
    features_table: str,
    books_table: str,
    store_location_map_table: str,
    locations_table: str,
    location: str,
    training_table: str,
) -> str:
    from google.cloud import bigquery

    client = bigquery.Client(project=project_id, location=location)
    table_id = f"{project_id}.{dataset_id}.{training_table}"

    query = f"""
    CREATE OR REPLACE TABLE `{table_id}` AS
    WITH date_spine AS (
      SELECT feature_date
      FROM UNNEST(GENERATE_DATE_ARRAY(
        (SELECT MIN(SAFE_CAST(sale_date AS DATE)) FROM `{project_id}.{dataset_id}.{sales_table}`),
        (SELECT MAX(SAFE_CAST(sale_date AS DATE)) FROM `{project_id}.{dataset_id}.{sales_table}`)
      )) AS feature_date
    ),
    series AS (
      SELECT DISTINCT
        s.isbn13,
        COALESCE(ls.wh_id, s.wh_id) AS wh_id
      FROM `{project_id}.{dataset_id}.{sales_table}` s
      LEFT JOIN `{project_id}.{dataset_id}.{store_location_map_table}` slm
        ON slm.store_id = s.store_id
      LEFT JOIN `{project_id}.{dataset_id}.{locations_table}` ls
        ON ls.location_id = slm.location_id
      WHERE s.sale_date IS NOT NULL
        AND COALESCE(ls.wh_id, s.wh_id) IS NOT NULL
    ),
    all_combinations AS (
      SELECT
        series.isbn13,
        series.wh_id,
        date_spine.feature_date
      FROM series
      CROSS JOIN date_spine
    ),
    daily_wh_sales AS (
      SELECT
        SAFE_CAST(s.sale_date AS DATE) AS feature_date,
        s.isbn13,
        COALESCE(ls.wh_id, s.wh_id) AS wh_id,
        SUM(COALESCE(CAST(s.qty_sold AS FLOAT64), 0)) AS qty_sold,
        SUM(COALESCE(CAST(s.revenue AS FLOAT64), 0)) AS revenue,
        SUM(COALESCE(CAST(s.tx_count AS FLOAT64), 0)) AS tx_count
      FROM `{project_id}.{dataset_id}.{sales_table}` s
      LEFT JOIN `{project_id}.{dataset_id}.{store_location_map_table}` slm
        ON slm.store_id = s.store_id
      LEFT JOIN `{project_id}.{dataset_id}.{locations_table}` ls
        ON ls.location_id = slm.location_id
      WHERE s.sale_date IS NOT NULL
      GROUP BY 1, 2, 3
    ),
    daily_wh_inventory AS (
      SELECT
        SAFE_CAST(i.snapshot_date AS DATE) AS feature_date,
        i.isbn13,
        ls.wh_id,
        SUM(COALESCE(CAST(i.on_hand AS FLOAT64), 0)) AS on_hand,
        SUM(COALESCE(CAST(i.reserved_qty AS FLOAT64), 0)) AS reserved_qty
      FROM `{project_id}.{dataset_id}.{inventory_table}` i
      JOIN `{project_id}.{dataset_id}.{locations_table}` ls
        ON ls.location_id = i.location_id
      WHERE i.snapshot_date IS NOT NULL
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
        FROM `{project_id}.{dataset_id}.{features_table}`
      )
      WHERE row_num = 1
    ),
    enriched AS (
      SELECT
        c.feature_date,
        c.isbn13,
        c.wh_id,
        COALESCE(s.qty_sold, 0) AS qty_sold,
        COALESCE(inv.on_hand, 0) AS on_hand,
        COALESCE(inv.reserved_qty, 0) AS reserved_qty,
        CAST(COALESCE(f.is_holiday, FALSE) AS INT64) AS holiday_flag,
        COALESCE(f.day_of_week, EXTRACT(DAYOFWEEK FROM c.feature_date)) AS day_of_week,
        COALESCE(f.month, EXTRACT(MONTH FROM c.feature_date)) AS month,
        CAST(COALESCE(f.is_weekend, EXTRACT(DAYOFWEEK FROM c.feature_date) IN (1, 7)) AS INT64) AS weekend_flag,
        COALESCE(f.event_nearby_days, 0) AS event_nearby_days,
        COALESCE(f.sns_mentions_1d, 0) AS sns_mentions_1d,
        COALESCE(f.sns_mentions_7d, 0) AS sns_mentions_7d,
        COALESCE(f.book_age_days, 0) AS book_age_days,
        COALESCE(f.days_since_last_stockout, 0) AS days_since_last_stockout,
        b.category_id,
        b.price_tier,
        COALESCE(b.sales_point, 0) AS sales_point,
        CAST(COALESCE(b.is_bestseller_flag, FALSE) AS INT64) AS bestseller_flag,
        COALESCE(b.author_experience_years, 0) AS author_experience_years
      FROM all_combinations c
      LEFT JOIN daily_wh_sales s
        ON s.feature_date = c.feature_date
       AND s.isbn13 = c.isbn13
       AND s.wh_id = c.wh_id
      LEFT JOIN daily_wh_inventory inv
        ON inv.feature_date = c.feature_date
       AND inv.isbn13 = c.isbn13
       AND inv.wh_id = c.wh_id
      LEFT JOIN features_dedup f
        ON f.isbn13 = c.isbn13
       AND SAFE_CAST(f.feature_date AS DATE) = c.feature_date
      LEFT JOIN `{project_id}.{dataset_id}.{books_table}` b
        ON b.isbn13 = c.isbn13
      WHERE COALESCE(f.book_age_days, 0) >= 0
    )
    SELECT
      *,
      LAG(qty_sold, 1) OVER (
        PARTITION BY isbn13, wh_id ORDER BY feature_date
      ) AS qty_lag_1,
      LAG(qty_sold, 7) OVER (
        PARTITION BY isbn13, wh_id ORDER BY feature_date
      ) AS qty_lag_7,
      AVG(qty_sold) OVER (
        PARTITION BY isbn13, wh_id
        ORDER BY feature_date
        ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
      ) AS qty_rolling_7d,
      AVG(qty_sold) OVER (
        PARTITION BY isbn13, wh_id
        ORDER BY feature_date
        ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
      ) AS qty_rolling_28d
    FROM enriched
    WHERE qty_sold IS NOT NULL
    """

    client.query(query).result()
    return table_id


@dsl.component(
    base_image="python:3.12-slim",
    packages_to_install=["google-cloud-bigquery"],
)
def validate_training_dataset(
    project_id: str,
    dataset_id: str,
    location: str,
    training_table: str,
    validation_table: str,
    business_timezone: str,
    max_data_lag_days: int,
    min_training_rows: int,
    min_time_series_count: int,
    max_required_null_ratio: float,
    max_zero_sales_ratio: float,
) -> str:
    from google.cloud import bigquery

    client = bigquery.Client(project=project_id, location=location)
    source_table_id = f"{project_id}.{dataset_id}.{training_table}"
    validation_table_id = f"{project_id}.{dataset_id}.{validation_table}"

    query = f"""
    CREATE TABLE IF NOT EXISTS `{validation_table_id}` (
      validation_date DATE NOT NULL,
      training_table STRING NOT NULL,
      row_count INT64 NOT NULL,
      time_series_count INT64 NOT NULL,
      min_feature_date DATE,
      max_feature_date DATE,
      zero_sales_ratio FLOAT64 NOT NULL,
      required_null_ratio FLOAT64 NOT NULL,
      validation_status STRING NOT NULL,
      reject_reason STRING,
      created_at TIMESTAMP NOT NULL
    )
    PARTITION BY validation_date
    CLUSTER BY training_table, validation_status;

    DELETE FROM `{validation_table_id}`
    WHERE validation_date = CURRENT_DATE(@business_timezone)
      AND training_table = @training_table;

    INSERT INTO `{validation_table_id}` (
      validation_date,
      training_table,
      row_count,
      time_series_count,
      min_feature_date,
      max_feature_date,
      zero_sales_ratio,
      required_null_ratio,
      validation_status,
      reject_reason,
      created_at
    )
    WITH metrics AS (
      SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT CONCAT(isbn13, '#', CAST(wh_id AS STRING))) AS time_series_count,
        MIN(feature_date) AS min_feature_date,
        MAX(feature_date) AS max_feature_date,
        SAFE_DIVIDE(COUNTIF(qty_sold = 0), COUNT(*)) AS zero_sales_ratio,
        SAFE_DIVIDE(
          COUNTIF(
            day_of_week IS NULL
            OR month IS NULL
            OR holiday_flag IS NULL
            OR weekend_flag IS NULL
            OR bestseller_flag IS NULL
          ),
          COUNT(*)
        ) AS required_null_ratio
      FROM `{source_table_id}`
    ),
    decisions AS (
      SELECT
        *,
        ARRAY_TO_STRING(
          ARRAY(
            SELECT reason
            FROM UNNEST([
              IF(row_count < @min_training_rows, 'row_count_below_threshold', NULL),
              IF(time_series_count < @min_time_series_count, 'time_series_count_below_threshold', NULL),
              IF(
                max_feature_date < DATE_SUB(CURRENT_DATE(@business_timezone), INTERVAL @max_data_lag_days DAY),
                'training_data_stale',
                NULL
              ),
              IF(required_null_ratio > @max_required_null_ratio, 'required_null_ratio_above_threshold', NULL),
              IF(zero_sales_ratio > @max_zero_sales_ratio, 'zero_sales_ratio_above_threshold', NULL)
            ]) AS reason
            WHERE reason IS NOT NULL
          ),
          ';'
        ) AS reject_reason
      FROM metrics
    )
    SELECT
      CURRENT_DATE(@business_timezone) AS validation_date,
      @training_table AS training_table,
      row_count,
      time_series_count,
      min_feature_date,
      max_feature_date,
      zero_sales_ratio,
      required_null_ratio,
      IF(reject_reason = '', 'PASSED', 'FAILED') AS validation_status,
      NULLIF(reject_reason, '') AS reject_reason,
      CURRENT_TIMESTAMP() AS created_at
    FROM decisions;

    ASSERT (
      SELECT validation_status = 'PASSED'
      FROM `{validation_table_id}`
      WHERE validation_date = CURRENT_DATE(@business_timezone)
        AND training_table = @training_table
      ORDER BY created_at DESC
      LIMIT 1
    ) AS 'Training validation failed. See training_validation_log.';
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("business_timezone", "STRING", business_timezone),
            bigquery.ScalarQueryParameter("max_data_lag_days", "INT64", max_data_lag_days),
            bigquery.ScalarQueryParameter("training_table", "STRING", training_table),
            bigquery.ScalarQueryParameter("min_training_rows", "INT64", min_training_rows),
            bigquery.ScalarQueryParameter("min_time_series_count", "INT64", min_time_series_count),
            bigquery.ScalarQueryParameter("max_required_null_ratio", "FLOAT64", max_required_null_ratio),
            bigquery.ScalarQueryParameter("max_zero_sales_ratio", "FLOAT64", max_zero_sales_ratio),
        ]
    )
    client.query(query, job_config=job_config).result()
    return validation_table_id


@dsl.component(
    base_image="python:3.12-slim",
    packages_to_install=["google-cloud-bigquery"],
)
def write_baseline_backtest(
    project_id: str,
    dataset_id: str,
    location: str,
    training_table: str,
    baseline_table: str,
    business_timezone: str,
    holdout_days: int,
) -> str:
    from google.cloud import bigquery

    client = bigquery.Client(project=project_id, location=location)
    source_table_id = f"{project_id}.{dataset_id}.{training_table}"
    baseline_table_id = f"{project_id}.{dataset_id}.{baseline_table}"

    query = f"""
    CREATE TABLE IF NOT EXISTS `{baseline_table_id}` (
      eval_date DATE NOT NULL,
      training_table STRING NOT NULL,
      holdout_days INT64 NOT NULL,
      baseline_model STRING NOT NULL,
      row_count INT64 NOT NULL,
      mae FLOAT64,
      rmse FLOAT64,
      wape FLOAT64,
      smape FLOAT64,
      p50_abs_error FLOAT64,
      p90_abs_error FLOAT64,
      bias FLOAT64,
      created_at TIMESTAMP NOT NULL
    )
    PARTITION BY eval_date
    CLUSTER BY training_table, baseline_model;

    DELETE FROM `{baseline_table_id}`
    WHERE eval_date = CURRENT_DATE(@business_timezone)
      AND training_table = @training_table
      AND holdout_days = @holdout_days;

    INSERT INTO `{baseline_table_id}` (
      eval_date,
      training_table,
      holdout_days,
      baseline_model,
      row_count,
      mae,
      rmse,
      wape,
      smape,
      p50_abs_error,
      p90_abs_error,
      bias,
      created_at
    )
    WITH dataset AS (
      SELECT
        feature_date,
        isbn13,
        wh_id,
        CAST(qty_sold AS FLOAT64) AS actual_qty,
        AVG(CAST(qty_sold AS FLOAT64)) OVER (
          PARTITION BY isbn13, wh_id
          ORDER BY feature_date
          ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
        ) AS ma_7d,
        AVG(CAST(qty_sold AS FLOAT64)) OVER (
          PARTITION BY isbn13, wh_id
          ORDER BY feature_date
          ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
        ) AS ma_28d,
        LAG(CAST(qty_sold AS FLOAT64), 7) OVER (
          PARTITION BY isbn13, wh_id
          ORDER BY feature_date
        ) AS same_weekday
      FROM `{source_table_id}`
    ),
    holdout AS (
      SELECT *
      FROM dataset
      WHERE feature_date > DATE_SUB(
        (SELECT MAX(feature_date) FROM dataset),
        INTERVAL @holdout_days DAY
      )
    ),
    scored AS (
      SELECT 'ma_7d' AS baseline_model, actual_qty, COALESCE(ma_7d, 0) AS predicted_qty
      FROM holdout
      UNION ALL
      SELECT 'ma_28d' AS baseline_model, actual_qty, COALESCE(ma_28d, 0) AS predicted_qty
      FROM holdout
      UNION ALL
      SELECT 'same_weekday' AS baseline_model, actual_qty, COALESCE(same_weekday, 0) AS predicted_qty
      FROM holdout
    )
    SELECT
      CURRENT_DATE(@business_timezone) AS eval_date,
      @training_table AS training_table,
      @holdout_days AS holdout_days,
      baseline_model,
      COUNT(*) AS row_count,
      AVG(ABS(actual_qty - predicted_qty)) AS mae,
      SQRT(AVG(POW(actual_qty - predicted_qty, 2))) AS rmse,
      SAFE_DIVIDE(
        SUM(ABS(actual_qty - predicted_qty)),
        NULLIF(SUM(ABS(actual_qty)), 0)
      ) AS wape,
      AVG(
        SAFE_DIVIDE(
          ABS(actual_qty - predicted_qty),
          NULLIF((ABS(actual_qty) + ABS(predicted_qty)) / 2, 0)
        )
      ) AS smape,
      APPROX_QUANTILES(ABS(actual_qty - predicted_qty), 100)[OFFSET(50)] AS p50_abs_error,
      APPROX_QUANTILES(ABS(actual_qty - predicted_qty), 100)[OFFSET(90)] AS p90_abs_error,
      AVG(predicted_qty - actual_qty) AS bias,
      CURRENT_TIMESTAMP() AS created_at
    FROM scored
    GROUP BY baseline_model;
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("business_timezone", "STRING", business_timezone),
            bigquery.ScalarQueryParameter("training_table", "STRING", training_table),
            bigquery.ScalarQueryParameter("holdout_days", "INT64", holdout_days),
        ]
    )
    client.query(query, job_config=job_config).result()
    return baseline_table_id


@dsl.component(
    base_image="python:3.12-slim",
    packages_to_install=["google-cloud-bigquery"],
)
def train_demand_model(
    project_id: str,
    dataset_id: str,
    location: str,
    training_table: str,
    model_name: str,
) -> str:
    from google.cloud import bigquery

    client = bigquery.Client(project=project_id, location=location)
    model_id = f"{project_id}.{dataset_id}.{model_name}"
    source_table_id = f"{project_id}.{dataset_id}.{training_table}"

    query = f"""
    CREATE OR REPLACE MODEL `{model_id}`
    OPTIONS(
      MODEL_TYPE = 'ARIMA_PLUS_XREG',
      TIME_SERIES_TIMESTAMP_COL = 'feature_date',
      TIME_SERIES_DATA_COL = 'qty_sold',
      TIME_SERIES_ID_COL = ['isbn13', 'wh_id'],
      HORIZON = 5,
      DATA_FREQUENCY = 'DAILY',
      AUTO_ARIMA = TRUE,
      AUTO_ARIMA_MAX_ORDER = 2,
      CLEAN_SPIKES_AND_DIPS = TRUE,
      ADJUST_STEP_CHANGES = TRUE,
      HOLIDAY_REGION = 'KR',
      TIME_SERIES_LENGTH_FRACTION = 0.6,
      MIN_TIME_SERIES_LENGTH = 90
    ) AS
    SELECT
      feature_date,
      isbn13,
      wh_id,
      qty_sold,
      day_of_week,
      month,
      holiday_flag,
      weekend_flag,
      COALESCE(event_nearby_days, 0) AS event_nearby_days,
      COALESCE(book_age_days, 0) AS book_age_days,
      COALESCE(sales_point, 0) AS sales_point,
      bestseller_flag,
      COALESCE(author_experience_years, 0) AS author_experience_years
    FROM `{source_table_id}`
    WHERE qty_sold IS NOT NULL
    """

    client.query(query).result()
    return model_id


@dsl.component(
    base_image="python:3.12-slim",
    packages_to_install=["google-cloud-bigquery"],
)
def evaluate_demand_model(
    project_id: str,
    dataset_id: str,
    location: str,
    model_name: str,
) -> str:
    from google.cloud import bigquery

    client = bigquery.Client(project=project_id, location=location)
    model_id = f"{project_id}.{dataset_id}.{model_name}"
    eval_table_id = f"{project_id}.{dataset_id}.{model_name}_evaluation"

    query = f"""
    CREATE OR REPLACE TABLE `{eval_table_id}` AS
    SELECT *
    FROM ML.EVALUATE(MODEL `{model_id}`)
    """

    client.query(query).result()
    return eval_table_id


@dsl.component(
    base_image="python:3.12-slim",
    packages_to_install=["google-cloud-bigquery"],
)
def write_batch_forecast(
    project_id: str,
    dataset_id: str,
    location: str,
    sales_table: str,
    store_location_map_table: str,
    locations_table: str,
    training_table: str,
    model_name: str,
    forecast_table: str,
    business_timezone: str,
    max_data_lag_days: int,
) -> str:
    from google.cloud import bigquery

    client = bigquery.Client(project=project_id, location=location)
    model_id = f"{project_id}.{dataset_id}.{model_name}"
    source_table_id = f"{project_id}.{dataset_id}.{training_table}"
    forecast_table_id = f"{project_id}.{dataset_id}.{forecast_table}"

    query = f"""
    DECLARE run_date DATE DEFAULT CURRENT_DATE(@business_timezone);
    DECLARE max_feature_date DATE DEFAULT (
      SELECT MAX(feature_date) FROM `{source_table_id}`
    );
    DECLARE max_allowed_feature_date DATE DEFAULT DATE_SUB(
      run_date,
      INTERVAL @max_data_lag_days DAY
    );

    ASSERT max_feature_date >= max_allowed_feature_date AS
      'Training data is stale. Refusing to write batch forecasts.';

    DELETE FROM `{forecast_table_id}`
    WHERE prediction_date = run_date;

    CREATE TEMP TABLE wh_predictions AS
    WITH latest_features AS (
      SELECT * EXCEPT(row_num)
      FROM (
        SELECT
          *,
          ROW_NUMBER() OVER (
            PARTITION BY isbn13, wh_id
            ORDER BY feature_date DESC
          ) AS row_num
        FROM `{source_table_id}`
      )
      WHERE row_num = 1
    ),
    future_features AS (
      SELECT
        DATE_ADD(feature_date, INTERVAL offset DAY) AS feature_date,
        isbn13,
        wh_id,
        EXTRACT(DAYOFWEEK FROM DATE_ADD(feature_date, INTERVAL offset DAY)) AS day_of_week,
        EXTRACT(MONTH FROM DATE_ADD(feature_date, INTERVAL offset DAY)) AS month,
        CAST(EXTRACT(DAYOFWEEK FROM DATE_ADD(feature_date, INTERVAL offset DAY)) IN (1, 7) AS INT64) AS weekend_flag,
        CAST(FALSE AS INT64) AS holiday_flag,
        GREATEST(COALESCE(event_nearby_days, 0) - offset, 0) AS event_nearby_days,
        COALESCE(book_age_days, 0) + offset AS book_age_days,
        COALESCE(sales_point, 0) AS sales_point,
        bestseller_flag,
        COALESCE(author_experience_years, 0) AS author_experience_years
      FROM latest_features
      CROSS JOIN UNNEST(GENERATE_ARRAY(1, 5)) AS offset
    )
    SELECT
      run_date AS prediction_date,
      DATE(forecast_timestamp) AS target_date,
      isbn13,
      wh_id,
      GREATEST(CAST(forecast_value AS FLOAT64), 0) AS predicted_wh_demand,
      GREATEST(CAST(prediction_interval_lower_bound AS FLOAT64), 0) AS confidence_low,
      GREATEST(CAST(prediction_interval_upper_bound AS FLOAT64), 0) AS confidence_high
    FROM ML.FORECAST(
      MODEL `{model_id}`,
      STRUCT(5 AS horizon, 0.8 AS confidence_level),
      (
        SELECT
          isbn13,
          wh_id,
          feature_date,
          day_of_week,
          month,
          holiday_flag,
          weekend_flag,
          COALESCE(event_nearby_days, 0) AS event_nearby_days,
          COALESCE(book_age_days, 0) AS book_age_days,
          COALESCE(sales_point, 0) AS sales_point,
          bestseller_flag,
          COALESCE(author_experience_years, 0) AS author_experience_years
        FROM future_features
      )
      )
    WHERE DATE(forecast_timestamp) BETWEEN (
      SELECT MIN(feature_date) FROM future_features
    ) AND (
      SELECT MAX(feature_date) FROM future_features
    );

    INSERT INTO `{forecast_table_id}` (
      prediction_date,
      target_date,
      isbn13,
      store_id,
      predicted_demand,
      confidence_low,
      confidence_high,
      model_version,
      inference_ms
    )
    WITH stores AS (
      SELECT
        store_id,
        wh_id,
        COUNT(*) OVER (PARTITION BY wh_id) AS store_count
      FROM (
        SELECT DISTINCT
          slm.store_id,
          ls.wh_id
        FROM `{project_id}.{dataset_id}.{store_location_map_table}` slm
        JOIN `{project_id}.{dataset_id}.{locations_table}` ls
          ON ls.location_id = slm.location_id
        WHERE ls.location_type LIKE 'STORE%'
          AND ls.wh_id IS NOT NULL
      )
    ),
    recent_store_sales AS (
      SELECT
        s.isbn13,
        st.wh_id,
        s.store_id,
        SUM(COALESCE(CAST(s.qty_sold AS FLOAT64), 0)) AS store_qty
      FROM `{project_id}.{dataset_id}.{sales_table}` s
      JOIN stores st
        ON st.store_id = s.store_id
      WHERE SAFE_CAST(s.sale_date AS DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
      GROUP BY 1, 2, 3
    ),
    store_shares AS (
      SELECT
        st.wh_id,
        wp.isbn13,
        st.store_id,
        COALESCE(
          SAFE_DIVIDE(
            rss.store_qty,
            SUM(rss.store_qty) OVER (PARTITION BY wp.isbn13, st.wh_id)
          ),
          SAFE_DIVIDE(1, st.store_count)
        ) AS demand_share
      FROM wh_predictions wp
      JOIN stores st
        ON st.wh_id = wp.wh_id
      LEFT JOIN recent_store_sales rss
        ON rss.isbn13 = wp.isbn13
       AND rss.wh_id = st.wh_id
       AND rss.store_id = st.store_id
    ),
    allocated_forecasts AS (
      SELECT
        wp.prediction_date,
        wp.target_date,
        wp.isbn13,
        ss.store_id,
        wp.predicted_wh_demand * ss.demand_share AS predicted_demand,
        wp.confidence_low * ss.demand_share AS confidence_low,
        wp.confidence_high * ss.demand_share AS confidence_high
      FROM wh_predictions wp
      JOIN store_shares ss
        ON ss.isbn13 = wp.isbn13
       AND ss.wh_id = wp.wh_id
    )
    SELECT
      prediction_date,
      target_date,
      isbn13,
      store_id,
      CAST(SUM(predicted_demand) AS NUMERIC) AS predicted_demand,
      CAST(SUM(confidence_low) AS NUMERIC) AS confidence_low,
      CAST(SUM(confidence_high) AS NUMERIC) AS confidence_high,
      @model_name AS model_version,
      CAST(NULL AS INT64) AS inference_ms
    FROM allocated_forecasts
    GROUP BY 1, 2, 3, 4
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("model_name", "STRING", model_name),
            bigquery.ScalarQueryParameter("business_timezone", "STRING", business_timezone),
            bigquery.ScalarQueryParameter("max_data_lag_days", "INT64", max_data_lag_days),
        ]
    )
    client.query(query, job_config=job_config).result()
    return forecast_table_id


def create_pipeline():
    @dsl.pipeline(
        name="bookflow-existing-books-forecast",
        description="Builds the existing-books training dataset, trains a demand model, evaluates it, and writes batch forecasts.",
    )
    def bookflow_existing_books_forecast(
        project_id: str,
        dataset_id: str,
        staging_bucket: str,
        models_bucket: str,
        source_object: str,
        bq_location: str,
        sales_table: str,
        inventory_table: str,
        features_table: str,
        books_table: str,
        locations_table: str,
        store_location_map_table: str,
        training_table: str,
        model_name: str,
        forecast_table: str,
        validation_table: str = "training_validation_log",
        baseline_table: str = "forecast_baseline_metrics",
        business_timezone: str = "Asia/Seoul",
        max_data_lag_days: int = 1,
        min_training_rows: int = 1000000,
        min_time_series_count: int = 1000,
        max_required_null_ratio: float = 0.01,
        max_zero_sales_ratio: float = 0.95,
        baseline_holdout_days: int = 28,
    ):
        runtime_config = validate_runtime_config(
            project_id=project_id,
            dataset_id=dataset_id,
            staging_bucket=staging_bucket,
            models_bucket=models_bucket,
            source_object=source_object,
        )
        runtime_config.set_caching_options(False)

        training_dataset = build_training_dataset(
            project_id=project_id,
            dataset_id=dataset_id,
            sales_table=sales_table,
            inventory_table=inventory_table,
            features_table=features_table,
            books_table=books_table,
            store_location_map_table=store_location_map_table,
            locations_table=locations_table,
            location=bq_location,
            training_table=training_table,
        ).after(runtime_config)
        training_dataset.set_caching_options(False)

        training_validation = validate_training_dataset(
            project_id=project_id,
            dataset_id=dataset_id,
            location=bq_location,
            training_table=training_table,
            validation_table=validation_table,
            business_timezone=business_timezone,
            max_data_lag_days=max_data_lag_days,
            min_training_rows=min_training_rows,
            min_time_series_count=min_time_series_count,
            max_required_null_ratio=max_required_null_ratio,
            max_zero_sales_ratio=max_zero_sales_ratio,
        ).after(training_dataset)
        training_validation.set_caching_options(False)

        baseline_backtest = write_baseline_backtest(
            project_id=project_id,
            dataset_id=dataset_id,
            location=bq_location,
            training_table=training_table,
            baseline_table=baseline_table,
            business_timezone=business_timezone,
            holdout_days=baseline_holdout_days,
        ).after(training_validation)
        baseline_backtest.set_caching_options(False)

        model = train_demand_model(
            project_id=project_id,
            dataset_id=dataset_id,
            location=bq_location,
            training_table=training_table,
            model_name=model_name,
        ).after(baseline_backtest)
        model.set_caching_options(False)

        evaluation = evaluate_demand_model(
            project_id=project_id,
            dataset_id=dataset_id,
            location=bq_location,
            model_name=model_name,
        ).after(model)
        evaluation.set_caching_options(False)

        forecast = write_batch_forecast(
            project_id=project_id,
            dataset_id=dataset_id,
            location=bq_location,
            sales_table=sales_table,
            store_location_map_table=store_location_map_table,
            locations_table=locations_table,
            training_table=training_table,
            model_name=model_name,
            forecast_table=forecast_table,
            business_timezone=business_timezone,
            max_data_lag_days=max_data_lag_days,
        ).after(evaluation)
        forecast.set_caching_options(False)

    return bookflow_existing_books_forecast


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compile the BOOKFLOW existing-books KFP v2 pipeline JSON."
    )
    parser.add_argument(
        "--output-json",
        default=os.getenv(
            ENV_OUTPUT_JSON,
            str(Path(__file__).resolve().with_name("bookflow-existing-books-pipeline.json")),
        ),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    output_json = Path(args.output_json).resolve()
    output_json.parent.mkdir(parents=True, exist_ok=True)

    pipeline_func = create_pipeline()
    compiler.Compiler().compile(
        pipeline_func=pipeline_func,
        package_path=str(output_json),
    )

    print(f"Compiled KFP v2 pipeline spec: {output_json}")


if __name__ == "__main__":
    main()
