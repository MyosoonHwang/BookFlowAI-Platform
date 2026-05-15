# BOOKFLOW Store Demand Champion Endpoint

## Current Model

- Model version: `champion-20260515-v1`
- Artifact source: `gs://project-8ab6bf05-54d2-4f5d-b8d-bookflow-models/custom-training/store-demand-champion-20260515-lowcost-v1/`
- Endpoint target: `bookflow-forecast-endpoint`
- Endpoint region: `asia-northeast1`
- Endpoint network: private `bookflow-vpc`
- Vertex Model resource: `projects/476598540719/locations/asia-northeast1/models/3223031419848622080`
- Serving image: `asia-northeast1-docker.pkg.dev/project-8ab6bf05-54d2-4f5d-b8d/bookflow-serving/store-demand-champion:20260515-v1`

## Performance

Holdout window: `2026-05-01` through `2026-05-14`

| Segment | WAPE | Notes |
|---|---:|---|
| all | 0.5249 | Low-cost champion policy |
| high | 0.5203 | HistGradientBoosting |
| medium | 1.0030 | ma7 fallback |

This is suitable for PoC/internal pilot and manager-reviewed recommendations. It is not suitable for fully automatic ordering.

## Online Prediction Request

Endpoint route: `/predict`

```json
{
  "instances": [
    {
      "store_id": 1,
      "wh_id": 1,
      "channel": "offline",
      "location_type": "STORE_OFFLINE",
      "store_size": "L",
      "region": "수도권",
      "on_hand": 120,
      "reserved_qty": 3,
      "safety_stock": 15,
      "holiday_flag": 0,
      "day_of_week": 6,
      "month": 5,
      "weekend_flag": 0,
      "event_nearby_days": 0,
      "sns_mentions_1d": 120,
      "sns_mentions_7d": 600,
      "book_age_days": 300,
      "days_since_last_stockout": 20,
      "category_id": 101,
      "price_tier": "MID",
      "sales_point": 50000,
      "bestseller_flag": 0,
      "author_experience_years": 7,
      "qty_lag_1": 3,
      "qty_lag_7": 4,
      "qty_rolling_7d": 3.5,
      "qty_rolling_28d": 3.2,
      "demand_segment": "high"
    }
  ]
}
```

Response:

```json
{
  "predictions": [
    {
      "predicted_demand": 3.4821,
      "confidence_low": 2.6116,
      "confidence_high": 4.3526,
      "model_version": "champion-20260515-v1",
      "inference_ms": 3
    }
  ]
}
```

## Cost Warning

Deploying this model to Vertex AI Endpoint with `min_replica_count=1` starts continuous online serving cost until the model is undeployed.

For nightly forecasts, prefer the existing batch prediction path unless AWS/dashboard needs real-time online inference.

## Deploy / Undeploy

Deploy script:

```powershell
powershell -ExecutionPolicy Bypass -File D:\gcp\BookFlowAI-Platform\scripts\gcp\deploy-store-demand-endpoint.ps1
```

Undeploy script:

```powershell
powershell -ExecutionPolicy Bypass -File D:\gcp\BookFlowAI-Platform\scripts\gcp\undeploy-store-demand-endpoint.ps1
```
