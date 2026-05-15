param(
    [string] $ProjectId = $env:BOOKFLOW_GCP_PROJECT_ID,
    [string] $DatasetId = $env:BOOKFLOW_BQ_DATASET,
    [string] $TrainingTable = "training_dataset_store",
    [int] $HoldoutDays = 28
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    throw "ProjectId is required. Pass -ProjectId or set BOOKFLOW_GCP_PROJECT_ID."
}
if ([string]::IsNullOrWhiteSpace($DatasetId)) {
    throw "DatasetId is required. Pass -DatasetId or set BOOKFLOW_BQ_DATASET."
}

$Sql = @"
DECLARE holdout_days INT64 DEFAULT $HoldoutDays;

CREATE TABLE IF NOT EXISTS ``$ProjectId.$DatasetId.pretrain_feature_screen`` (
  run_date DATE,
  training_table STRING,
  check_name STRING,
  segment STRING,
  row_count INT64,
  metric_1 FLOAT64,
  metric_2 FLOAT64,
  metric_3 FLOAT64,
  passed BOOL,
  notes STRING,
  created_at TIMESTAMP
);

DELETE FROM ``$ProjectId.$DatasetId.pretrain_feature_screen``
WHERE run_date = CURRENT_DATE('Asia/Seoul')
  AND training_table = '$TrainingTable';

INSERT INTO ``$ProjectId.$DatasetId.pretrain_feature_screen``
WITH base AS (
  SELECT *
  FROM ``$ProjectId.$DatasetId.$TrainingTable``
),
scored AS (
  SELECT
    *,
    AVG(qty_sold) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
      ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
    ) AS ma_28d,
    AVG(qty_sold) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
      ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS ma_7d
  FROM base
),
holdout AS (
  SELECT *
  FROM scored
  WHERE feature_date > DATE_SUB((SELECT MAX(feature_date) FROM base), INTERVAL holdout_days DAY)
),
baseline AS (
  SELECT
    'baseline_ma28' AS check_name,
    demand_segment AS segment,
    COUNT(*) AS row_count,
    SAFE_DIVIDE(SUM(ABS(qty_sold - COALESCE(ma_28d, 0))), NULLIF(SUM(ABS(qty_sold)), 0)) AS metric_1,
    AVG(ABS(qty_sold - COALESCE(ma_28d, 0))) AS metric_2,
    APPROX_QUANTILES(ABS(qty_sold - COALESCE(ma_28d, 0)), 100)[OFFSET(90)] AS metric_3,
    SAFE_DIVIDE(SUM(ABS(qty_sold - COALESCE(ma_28d, 0))), NULLIF(SUM(ABS(qty_sold)), 0)) < 1.0 AS passed,
    'metric_1=wape, metric_2=mae, metric_3=p90_abs_error' AS notes
  FROM holdout
  GROUP BY demand_segment
),
store_size AS (
  SELECT
    'store_size_uplift' AS check_name,
    store_size AS segment,
    COUNT(*) AS row_count,
    AVG(qty_sold) AS metric_1,
    SAFE_DIVIDE(AVG(qty_sold), NULLIF((SELECT AVG(qty_sold) FROM holdout), 0)) AS metric_2,
    AVG(on_hand) AS metric_3,
    COUNT(*) > 0 AS passed,
    'metric_1=avg_qty, metric_2=avg_qty_vs_global, metric_3=avg_on_hand' AS notes
  FROM holdout
  GROUP BY store_size
),
sns_effect AS (
  SELECT
    'sns_uplift' AS check_name,
    IF(sns_mentions_1d >= 500 OR sns_mentions_7d >= 1000, 'high_sns', 'normal_sns') AS segment,
    COUNT(*) AS row_count,
    AVG(qty_sold) AS metric_1,
    SAFE_DIVIDE(AVG(qty_sold), NULLIF((SELECT AVG(qty_sold) FROM holdout WHERE sns_mentions_1d < 500 AND sns_mentions_7d < 1000), 0)) AS metric_2,
    AVG(sns_mentions_1d) AS metric_3,
    COUNT(*) > 0 AS passed,
    'metric_1=avg_qty, metric_2=uplift_vs_normal_sns, metric_3=avg_sns_1d' AS notes
  FROM holdout
  GROUP BY segment
),
event_effect AS (
  SELECT
    'event_uplift' AS check_name,
    IF(event_nearby_days BETWEEN 0 AND 2 OR holiday_flag = 1, 'event_window', 'normal_day') AS segment,
    COUNT(*) AS row_count,
    AVG(qty_sold) AS metric_1,
    SAFE_DIVIDE(AVG(qty_sold), NULLIF((SELECT AVG(qty_sold) FROM holdout WHERE NOT (event_nearby_days BETWEEN 0 AND 2 OR holiday_flag = 1)), 0)) AS metric_2,
    AVG(event_nearby_days) AS metric_3,
    COUNT(*) > 0 AS passed,
    'metric_1=avg_qty, metric_2=uplift_vs_normal_day, metric_3=avg_event_nearby_days' AS notes
  FROM holdout
  GROUP BY segment
),
bestseller_effect AS (
  SELECT
    'bestseller_uplift' AS check_name,
    IF(bestseller_flag = 1, 'bestseller', 'non_bestseller') AS segment,
    COUNT(*) AS row_count,
    AVG(qty_sold) AS metric_1,
    SAFE_DIVIDE(AVG(qty_sold), NULLIF((SELECT AVG(qty_sold) FROM holdout WHERE bestseller_flag = 0), 0)) AS metric_2,
    AVG(sales_point) AS metric_3,
    COUNT(*) > 0 AS passed,
    'metric_1=avg_qty, metric_2=uplift_vs_non_bestseller, metric_3=avg_sales_point' AS notes
  FROM holdout
  GROUP BY segment
),
checks AS (
  SELECT * FROM baseline
  UNION ALL SELECT * FROM store_size
  UNION ALL SELECT * FROM sns_effect
  UNION ALL SELECT * FROM event_effect
  UNION ALL SELECT * FROM bestseller_effect
)
SELECT
  CURRENT_DATE('Asia/Seoul') AS run_date,
  '$TrainingTable' AS training_table,
  check_name,
  segment,
  row_count,
  metric_1,
  metric_2,
  metric_3,
  passed,
  notes,
  CURRENT_TIMESTAMP() AS created_at
FROM checks;

SELECT
  check_name,
  segment,
  row_count,
  ROUND(metric_1, 4) AS metric_1,
  ROUND(metric_2, 4) AS metric_2,
  ROUND(metric_3, 4) AS metric_3,
  passed,
  notes
FROM ``$ProjectId.$DatasetId.pretrain_feature_screen``
WHERE run_date = CURRENT_DATE('Asia/Seoul')
  AND training_table = '$TrainingTable'
ORDER BY check_name, segment;
"@

$Sql | bq query --use_legacy_sql=false
