param(
    [string] $ProjectId = $env:BOOKFLOW_GCP_PROJECT_ID,
    [string] $DatasetId = $env:BOOKFLOW_BQ_DATASET,
    [string] $TrainingTable = "training_dataset_store"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    throw "ProjectId is required. Pass -ProjectId or set BOOKFLOW_GCP_PROJECT_ID."
}
if ([string]::IsNullOrWhiteSpace($DatasetId)) {
    throw "DatasetId is required. Pass -DatasetId or set BOOKFLOW_BQ_DATASET."
}

$Sql = @"
WITH table_quality AS (
  SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT isbn13) AS isbn_count,
    COUNT(DISTINCT store_id) AS store_count,
    COUNT(DISTINCT CONCAT(isbn13, '#', CAST(store_id AS STRING))) AS series_count,
    MIN(feature_date) AS min_feature_date,
    MAX(feature_date) AS max_feature_date,
    DATE_DIFF(CURRENT_DATE('Asia/Seoul'), MAX(feature_date), DAY) AS data_lag_days,
    AVG(IF(qty_sold = 0, 1, 0)) AS zero_sales_ratio,
    AVG(IF(
      day_of_week IS NULL
      OR month IS NULL
      OR weekend_flag IS NULL
      OR bestseller_flag IS NULL
      OR store_id IS NULL
      OR wh_id IS NULL,
      1,
      0
    )) AS required_null_ratio
  FROM ``$ProjectId.$DatasetId.$TrainingTable``
),
best_baseline AS (
  SELECT
    demand_segment,
    ARRAY_AGG(
      STRUCT(baseline_model, wape, mae, p90_abs_error, bias)
      ORDER BY wape ASC
      LIMIT 1
    )[OFFSET(0)] AS best
  FROM ``$ProjectId.$DatasetId.pretrain_intermittent_baselines``
  WHERE run_date = CURRENT_DATE('Asia/Seoul')
    AND training_table = '$TrainingTable'
  GROUP BY demand_segment
),
feature_checks AS (
  SELECT
    MAX(IF(check_name = 'event_uplift' AND segment = 'event_window', metric_2, NULL)) AS event_uplift,
    MAX(IF(check_name = 'sns_uplift' AND segment = 'high_sns', metric_2, NULL)) AS sns_uplift,
    MAX(IF(check_name = 'bestseller_uplift' AND segment = 'bestseller', metric_2, NULL)) AS bestseller_uplift,
    MAX(IF(check_name = 'store_size_uplift' AND segment = 'L', metric_2, NULL)) AS large_store_uplift
  FROM ``$ProjectId.$DatasetId.pretrain_feature_screen``
  WHERE run_date = CURRENT_DATE('Asia/Seoul')
    AND training_table = '$TrainingTable'
),
gate AS (
  SELECT
    tq.*,
    MAX(IF(bb.demand_segment = 'high', bb.best.wape, NULL)) AS high_best_wape,
    MAX(IF(bb.demand_segment = 'medium', bb.best.wape, NULL)) AS medium_best_wape,
    MAX(IF(bb.demand_segment = 'low', bb.best.wape, NULL)) AS low_best_wape,
    fc.event_uplift,
    fc.sns_uplift,
    fc.bestseller_uplift,
    fc.large_store_uplift
  FROM table_quality tq
  CROSS JOIN best_baseline bb
  CROSS JOIN feature_checks fc
  GROUP BY
    row_count,
    isbn_count,
    store_count,
    series_count,
    min_feature_date,
    max_feature_date,
    data_lag_days,
    zero_sales_ratio,
    required_null_ratio,
    event_uplift,
    sns_uplift,
    bestseller_uplift,
    large_store_uplift
)
SELECT
  *,
  (
    row_count >= 1000000
    AND store_count = 14
    AND series_count >= 14000
    AND data_lag_days <= 1
    AND required_null_ratio <= 0.01
    AND high_best_wape <= 0.85
    AND medium_best_wape <= 1.05
    AND COALESCE(low_best_wape <= 1.05, TRUE)
    AND event_uplift >= 1.05
    AND bestseller_uplift >= 1.15
    AND large_store_uplift >= 1.02
  ) AS pretrain_gate_passed,
  ARRAY_TO_STRING(
    ARRAY(
      SELECT reason
      FROM UNNEST([
        IF(row_count < 1000000, 'row_count_below_1m', NULL),
        IF(store_count != 14, 'store_count_not_14_generate_py_basis', NULL),
        IF(series_count < 14000, 'series_count_below_14000', NULL),
        IF(data_lag_days > 1, 'data_stale', NULL),
        IF(required_null_ratio > 0.01, 'required_null_ratio_above_1pct', NULL),
        IF(high_best_wape > 0.85, 'high_wape_above_0_85', NULL),
        IF(medium_best_wape > 1.05, 'medium_wape_above_1_05', NULL),
        IF(COALESCE(low_best_wape > 1.05, FALSE), 'low_wape_above_1_05', NULL),
        IF(event_uplift < 1.05, 'event_uplift_below_1_05', NULL),
        IF(bestseller_uplift < 1.15, 'bestseller_uplift_below_1_15', NULL),
        IF(large_store_uplift < 1.02, 'large_store_uplift_below_1_02', NULL)
      ]) AS reason
      WHERE reason IS NOT NULL
    ),
    ';'
  ) AS reject_reasons
FROM gate;
"@

$Sql | bq query --use_legacy_sql=false
