# BOOKFLOW Forecast Model Improvement Plan

## Current Findings

- The latest successful pipeline wrote forecasts for only one target date. The pipeline used `horizon = 5`, but filtered `ML.FORECAST` output down to the first generated date.
- The latest `training_dataset` ends at `2026-04-30`, while the pipeline was run on `2026-05-15 KST`. The forecast output therefore wrote stale `2026-05-01` targets as if they were current.
- The schema workbook expects D+1 through D+5 output and about `5 x active books x active stores` forecast rows per run. Current output was `14,000` rows for one target date.
- The workbook describes store-level time series `(isbn13, store_id)`, but the current pipeline trains at warehouse grain `(isbn13, wh_id)` and allocates warehouse predictions down to stores. This is a pragmatic shortcut, but it hides store-level demand patterns.
- Existing AutoML model registry output succeeded, but the latest quality metrics are not production-ready: high percentage errors and near-zero `R2`.

## Immediate Guardrails

1. Block stale forecasts.
   The pipeline must fail before writing `forecast_results` if the latest training feature date is older than the allowed lag.

2. Block stale or malformed training data before training.
   The pipeline must write a row to `training_validation_log` and stop before model training when row count, series count, freshness, required null ratio, or zero-sales ratio fails the configured thresholds.

3. Write the full forecast horizon.
   Each successful batch forecast must contain all target dates D+1 through D+5, not only D+1.

4. Validate output shape.
   For each `prediction_date`, require one row per active `(target_date, isbn13, store_id)` combination, zero negative forecasts, and no null `predicted_demand`.

5. Keep endpoint deployment disabled.
   Do not deploy a model to the endpoint until offline evaluation and batch-output validation pass.

## Data Quality Phase

1. Align schema and physical tables.
   `sales_fact.sale_date` should be a `DATE`, not a `STRING`, or all model SQL must cast it consistently with explicit bad-row checks.

2. Decide the production grain.
   Preferred: train at `(isbn13, store_id)` as documented.
   Interim: keep `(isbn13, wh_id)` only if the decision engine accepts warehouse-level forecasts and store allocation is separately validated.

3. Separate stockout zeros from true demand zeros.
   Use `on_hand`, `reserved_qty`, `safety_stock`, and stockout flags so the model does not learn that unavailable inventory means zero demand.

4. Segment the catalog.
   Evaluate high-volume, medium-volume, low-volume, new, and intermittent books separately. Sparse retail demand makes global MAPE unreliable.

## Baselines Before Advanced Models

Every candidate model must beat simple baselines:

- Last observed same weekday.
- 7-day and 28-day moving averages.
- Seasonal naive forecast.
- Croston-style intermittent demand baseline for sparse ISBN-store series.

Promotion should be blocked if the candidate model does not beat baseline sMAPE/WAPE or has worse p90 absolute error.

Current 28-day holdout baseline on the warehouse-grain dataset:

- `ma_28d`: WAPE `1.1561`, MAE `0.8812`, p90 absolute error `1.5`
- `ma_7d`: WAPE `1.1923`, MAE `0.9088`, p90 absolute error `1.7143`
- `same_weekday`: WAPE `1.3833`, MAE `1.0543`, p90 absolute error `3.0`

These are not good enough as final business metrics, but they are the minimum bar for any trained candidate.

## Modeling Direction

1. BigQuery ML ARIMA_PLUS_XREG baseline
   Keep this as the transparent, low-operational-cost baseline. It is useful for fast iteration and explainable components.

2. Store-level AutoML Forecast candidate
   Rebuild the dataset at `(isbn13, store_id)` with known-future covariates and past-only covariates separated according to the workbook.

3. Probabilistic multi-horizon model candidate
   Consider TFT or DeepAR after data quality gates pass. These are better suited to many related series, known future covariates, static attributes, and uncertainty intervals.

## Evaluation Metrics

- Primary: WAPE, sMAPE, MAE, p90 absolute error.
- Secondary: RMSE, forecast bias, interval coverage.
- Avoid using MAPE alone because many book-store days have zero or near-zero sales.
- Evaluate by segment and by operational decision impact, not only global averages.

## Promotion Gate

A model can be promoted only when:

- Training data freshness passes.
- Output row count and D+1 through D+5 horizon completeness pass.
- Candidate beats baseline on WAPE or sMAPE for high/medium-volume segments.
- p90 absolute error is below the agreed operational threshold.
- Forecast bias is not materially over-ordering or under-ordering.
- Manual sample review for purchase-order recommendations passes.

## References

- Google Cloud BigQuery ML forecasting overview: https://cloud.google.com/bigquery/docs/forecasting-overview
- Google Cloud `ML.FORECAST` reference: https://cloud.google.com/bigquery/docs/reference/standard-sql/bigqueryml-syntax-forecast
- Google Cloud `ARIMA_PLUS_XREG` model reference: https://cloud.google.com/bigquery/docs/reference/standard-sql/bigqueryml-syntax-create-multivariate-time-series
- M5 forecasting competition paper: https://www.sciencedirect.com/science/article/pii/S0169207021001187
- Temporal Fusion Transformer paper: https://arxiv.org/abs/1912.09363
- DeepAR paper: https://arxiv.org/abs/1704.04110
- Croston intermittent demand paper: https://link.springer.com/article/10.1057/jors.1972.50
