param(
    [string] $ProjectId = $env:BOOKFLOW_GCP_PROJECT_ID,
    [string] $DatasetId = $env:BOOKFLOW_BQ_DATASET,
    [string] $TrainingTable = "training_dataset_store",
    [int] $LookbackDays = 56,
    [int] $HoldoutDays = 14
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    throw "ProjectId is required. Pass -ProjectId or set BOOKFLOW_GCP_PROJECT_ID."
}
if ([string]::IsNullOrWhiteSpace($DatasetId)) {
    throw "DatasetId is required. Pass -DatasetId or set BOOKFLOW_BQ_DATASET."
}

$Sql = @"
DECLARE lookback_days INT64 DEFAULT $LookbackDays;
DECLARE holdout_days INT64 DEFAULT $HoldoutDays;

CREATE TABLE IF NOT EXISTS ``$ProjectId.$DatasetId.pretrain_intermittent_baselines`` (
  run_date DATE,
  training_table STRING,
  baseline_model STRING,
  demand_segment STRING,
  row_count INT64,
  actual_sum FLOAT64,
  predicted_sum FLOAT64,
  mae FLOAT64,
  rmse FLOAT64,
  wape FLOAT64,
  smape FLOAT64,
  p50_abs_error FLOAT64,
  p90_abs_error FLOAT64,
  bias FLOAT64,
  passed BOOL,
  notes STRING,
  created_at TIMESTAMP
);

DELETE FROM ``$ProjectId.$DatasetId.pretrain_intermittent_baselines``
WHERE run_date = CURRENT_DATE('Asia/Seoul')
  AND training_table = '$TrainingTable';

INSERT INTO ``$ProjectId.$DatasetId.pretrain_intermittent_baselines``
WITH base AS (
  SELECT
    feature_date,
    isbn13,
    store_id,
    demand_segment,
    CAST(qty_sold AS FLOAT64) AS actual_qty
  FROM ``$ProjectId.$DatasetId.$TrainingTable``
),
features AS (
  SELECT
    *,
    AVG(actual_qty) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
      ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS ma_7d,
    AVG(actual_qty) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
      ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
    ) AS ma_28d,
    AVG(IF(actual_qty > 0, actual_qty, NULL)) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
      ROWS BETWEEN $LookbackDays PRECEDING AND 1 PRECEDING
    ) AS nonzero_mean_qty,
    AVG(IF(actual_qty > 0, 1.0, 0.0)) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
      ROWS BETWEEN $LookbackDays PRECEDING AND 1 PRECEDING
    ) AS nonzero_probability,
    LAG(actual_qty, 7) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
    ) AS same_weekday
  FROM base
),
holdout AS (
  SELECT *
  FROM features
  WHERE feature_date > DATE_SUB((SELECT MAX(feature_date) FROM base), INTERVAL holdout_days DAY)
),
calibration AS (
  SELECT *
  FROM features
  WHERE feature_date > DATE_SUB((SELECT MAX(feature_date) FROM base), INTERVAL holdout_days * 2 DAY)
    AND feature_date <= DATE_SUB((SELECT MAX(feature_date) FROM base), INTERVAL holdout_days DAY)
),
raw_scored AS (
  SELECT 'ma_7d' AS baseline_model, demand_segment, actual_qty, COALESCE(ma_7d, 0) AS predicted_qty
  FROM calibration
  UNION ALL
  SELECT 'ma_28d', demand_segment, actual_qty, COALESCE(ma_28d, 0)
  FROM calibration
  UNION ALL
  SELECT
    'intermittent_probability_mean',
    demand_segment,
    actual_qty,
    COALESCE(nonzero_mean_qty, 0) * COALESCE(nonzero_probability, 0)
  FROM calibration
),
calibration_factors AS (
  SELECT
    baseline_model,
    demand_segment,
    LEAST(
      2.0,
      GREATEST(0.5, COALESCE(SAFE_DIVIDE(SUM(actual_qty), NULLIF(SUM(predicted_qty), 0)), 1.0))
    ) AS calibration_factor
  FROM raw_scored
  GROUP BY baseline_model, demand_segment
),
scored AS (
  SELECT 'ma_7d' AS baseline_model, demand_segment, actual_qty, COALESCE(ma_7d, 0) AS predicted_qty
  FROM holdout
  UNION ALL
  SELECT 'ma_28d', demand_segment, actual_qty, COALESCE(ma_28d, 0)
  FROM holdout
  UNION ALL
  SELECT 'same_weekday', demand_segment, actual_qty, COALESCE(same_weekday, 0)
  FROM holdout
  UNION ALL
  SELECT
    'intermittent_probability_mean',
    demand_segment,
    actual_qty,
    COALESCE(nonzero_mean_qty, 0) * COALESCE(nonzero_probability, 0)
  FROM holdout
  UNION ALL
  SELECT
    'sba_adjusted_intermittent',
    demand_segment,
    actual_qty,
    0.95 * COALESCE(nonzero_mean_qty, 0) * COALESCE(nonzero_probability, 0)
  FROM holdout
  UNION ALL
  SELECT
    'calibrated_ma_7d',
    h.demand_segment,
    h.actual_qty,
    COALESCE(h.ma_7d, 0) * COALESCE(cf.calibration_factor, 1.0)
  FROM holdout h
  LEFT JOIN calibration_factors cf
    ON cf.baseline_model = 'ma_7d'
   AND cf.demand_segment = h.demand_segment
  UNION ALL
  SELECT
    'calibrated_ma_28d',
    h.demand_segment,
    h.actual_qty,
    COALESCE(h.ma_28d, 0) * COALESCE(cf.calibration_factor, 1.0)
  FROM holdout h
  LEFT JOIN calibration_factors cf
    ON cf.baseline_model = 'ma_28d'
   AND cf.demand_segment = h.demand_segment
  UNION ALL
  SELECT
    'calibrated_intermittent_probability_mean',
    h.demand_segment,
    h.actual_qty,
    COALESCE(h.nonzero_mean_qty, 0) * COALESCE(h.nonzero_probability, 0) * COALESCE(cf.calibration_factor, 1.0)
  FROM holdout h
  LEFT JOIN calibration_factors cf
    ON cf.baseline_model = 'intermittent_probability_mean'
   AND cf.demand_segment = h.demand_segment
),
metrics AS (
  SELECT
    baseline_model,
    demand_segment,
    COUNT(*) AS row_count,
    SUM(actual_qty) AS actual_sum,
    SUM(predicted_qty) AS predicted_sum,
    AVG(ABS(actual_qty - predicted_qty)) AS mae,
    SQRT(AVG(POW(actual_qty - predicted_qty, 2))) AS rmse,
    SAFE_DIVIDE(SUM(ABS(actual_qty - predicted_qty)), NULLIF(SUM(ABS(actual_qty)), 0)) AS wape,
    AVG(SAFE_DIVIDE(ABS(actual_qty - predicted_qty), NULLIF((ABS(actual_qty) + ABS(predicted_qty)) / 2, 0))) AS smape,
    APPROX_QUANTILES(ABS(actual_qty - predicted_qty), 100)[OFFSET(50)] AS p50_abs_error,
    APPROX_QUANTILES(ABS(actual_qty - predicted_qty), 100)[OFFSET(90)] AS p90_abs_error,
    AVG(predicted_qty - actual_qty) AS bias
  FROM scored
  GROUP BY baseline_model, demand_segment
)
SELECT
  CURRENT_DATE('Asia/Seoul') AS run_date,
  '$TrainingTable' AS training_table,
  baseline_model,
  demand_segment,
  row_count,
  actual_sum,
  predicted_sum,
  mae,
  rmse,
  wape,
  smape,
  p50_abs_error,
  p90_abs_error,
  bias,
  wape < 1.0 AS passed,
  'holdout_days=' || CAST(holdout_days AS STRING) || ', lookback_days=' || CAST(lookback_days AS STRING) AS notes,
  CURRENT_TIMESTAMP() AS created_at
FROM metrics;

SELECT
  baseline_model,
  demand_segment,
  row_count,
  ROUND(actual_sum, 4) AS actual_sum,
  ROUND(predicted_sum, 4) AS predicted_sum,
  ROUND(mae, 4) AS mae,
  ROUND(rmse, 4) AS rmse,
  ROUND(wape, 4) AS wape,
  ROUND(smape, 4) AS smape,
  ROUND(p50_abs_error, 4) AS p50_abs_error,
  ROUND(p90_abs_error, 4) AS p90_abs_error,
  ROUND(bias, 4) AS bias,
  passed
FROM ``$ProjectId.$DatasetId.pretrain_intermittent_baselines``
WHERE run_date = CURRENT_DATE('Asia/Seoul')
  AND training_table = '$TrainingTable'
ORDER BY demand_segment, wape, baseline_model;
"@

$Sql | bq query --use_legacy_sql=false
