# Forecast Pretraining Research Notes

This note records the modeling assumptions used before spending Vertex AI
training budget.

## Applied Principles

- Retail demand should be modeled at the operational decision grain when
  possible. For BOOKFLOW this means `(isbn13, store_id)` before the decision
  service decides branch replenishment.
- Use grouped related series instead of isolated per-book models. Book demand is
  sparse, so sharing information across ISBNs, stores, categories, and regions is
  important.
- Keep static covariates separate from time-varying known inputs and observed
  historical inputs:
  - Static: category, price tier, bestseller flag, author experience, store size,
    region.
  - Known future: day of week, month, weekend, holiday/event window.
  - Observed historical: sales lags, rolling sales, SNS mentions, inventory.
- For intermittent demand, do not trust global MAPE alone. Use WAPE, sMAPE, MAE,
  p90 absolute error, and segment-level checks.
- A trained model must beat simple baselines before promotion. Current preflight
  baseline is moving average over the latest holdout window.

## References

- M5 competition paper: retail forecasting with many grouped series,
  explanatory variables, uncertainty, and intermittent demand.
  https://www.sciencedirect.com/science/article/pii/S0169207021001187
- Temporal Fusion Transformer: static covariates, known future inputs, observed
  historical inputs, and interpretable multi-horizon forecasting.
  https://arxiv.org/abs/1912.09363
- DeepAR: one probabilistic model trained across many related time series.
  https://arxiv.org/abs/1704.04110
- Croston intermittent demand: separate treatment for sparse demand patterns.
  https://link.springer.com/article/10.1057/jors.1972.50

## Current Low-Cost Gate

Before running Vertex AI AutoML:

1. Build `training_dataset_store` at `(isbn13, store_id)`.
2. Confirm freshness, row count, series count, nulls, and zero-demand ratio.
3. Run `pretrain-store-feature-screen.ps1`.
4. Do not run Vertex AI unless the store-level feature screen shows meaningful
   lift for at least store size, bestseller status, SNS, or event windows, and
   the moving-average baseline leaves room to improve.
