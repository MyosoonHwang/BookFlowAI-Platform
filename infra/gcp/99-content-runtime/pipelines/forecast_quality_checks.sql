-- BOOKFLOW forecast quality checks.
-- Replace the DECLARE values when running manually, or convert them to query
-- parameters in orchestration. Replace ${PROJECT_ID} and ${DATASET_ID} during
-- deployment; do not commit environment-specific values here.

DECLARE prediction_date_param DATE DEFAULT CURRENT_DATE('Asia/Seoul');
DECLARE expected_horizon_days INT64 DEFAULT 5;

WITH forecast_scope AS (
  SELECT *
  FROM `${PROJECT_ID}.${DATASET_ID}.forecast_results`
  WHERE prediction_date = prediction_date_param
),
summary AS (
  SELECT
    prediction_date,
    COUNT(*) AS row_count,
    COUNT(DISTINCT target_date) AS horizon_days,
    MIN(target_date) AS min_target_date,
    MAX(target_date) AS max_target_date,
    COUNT(DISTINCT isbn13) AS isbn_count,
    COUNT(DISTINCT store_id) AS store_count,
    COUNTIF(predicted_demand IS NULL) AS null_predictions,
    COUNTIF(predicted_demand < 0) AS negative_predictions,
    COUNTIF(confidence_low < 0) AS negative_lower_bounds,
    COUNTIF(confidence_high < confidence_low) AS invalid_intervals
  FROM forecast_scope
  GROUP BY prediction_date
),
target_date_counts AS (
  SELECT
    target_date,
    COUNT(*) AS row_count
  FROM forecast_scope
  GROUP BY target_date
)
SELECT
  summary.*,
  ARRAY_AGG(
    STRUCT(target_date_counts.target_date, target_date_counts.row_count)
    ORDER BY target_date_counts.target_date
  ) AS target_date_row_counts,
  (
    horizon_days = expected_horizon_days
    AND null_predictions = 0
    AND negative_predictions = 0
    AND negative_lower_bounds = 0
    AND invalid_intervals = 0
  ) AS passed
FROM summary
JOIN target_date_counts
  ON TRUE
GROUP BY
  prediction_date,
  row_count,
  horizon_days,
  min_target_date,
  max_target_date,
  isbn_count,
  store_count,
  null_predictions,
  negative_predictions,
  negative_lower_bounds,
  invalid_intervals;
