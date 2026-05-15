-- BOOKFLOW baseline backtest for existing-book demand forecasting.
-- Replace ${PROJECT_ID} and ${DATASET_ID} during deployment.
-- The query evaluates simple baselines on the latest holdout window before
-- promoting a trained model.

DECLARE holdout_days INT64 DEFAULT 28;

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
  FROM `${PROJECT_ID}.${DATASET_ID}.training_dataset`
),
holdout AS (
  SELECT *
  FROM dataset
  WHERE feature_date > DATE_SUB(
    (SELECT MAX(feature_date) FROM dataset),
    INTERVAL holdout_days DAY
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
  AVG(predicted_qty - actual_qty) AS bias
FROM scored
GROUP BY baseline_model
ORDER BY wape, mae;
