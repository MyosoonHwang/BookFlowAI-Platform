import json
import os
import time
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from fastapi import FastAPI, HTTPException


FEATURE_COLUMNS = [
    "store_id",
    "wh_id",
    "channel",
    "location_type",
    "store_size",
    "region",
    "on_hand",
    "reserved_qty",
    "safety_stock",
    "holiday_flag",
    "day_of_week",
    "month",
    "weekend_flag",
    "event_nearby_days",
    "sns_mentions_1d",
    "sns_mentions_7d",
    "book_age_days",
    "days_since_last_stockout",
    "category_id",
    "price_tier",
    "sales_point",
    "bestseller_flag",
    "author_experience_years",
    "qty_lag_1",
    "qty_lag_7",
    "qty_rolling_7d",
    "qty_rolling_28d",
    "demand_segment",
]

MODEL_DIR = Path(os.environ.get("MODEL_DIR", "/app/model_artifact"))
MODEL = joblib.load(MODEL_DIR / "model.joblib")
METADATA = json.loads((MODEL_DIR / "metrics.json").read_text(encoding="utf-8"))
MODEL_VERSION = os.environ.get("MODEL_VERSION", "champion-20260515-v1")

app = FastAPI()


def _predict_policy(frame: pd.DataFrame) -> tuple[np.ndarray, int]:
    segment = frame["demand_segment"].fillna("low")
    high_mask = segment.eq("high").to_numpy()
    medium_mask = segment.eq("medium").to_numpy()
    pred = np.zeros(len(frame), dtype=float)
    start = time.perf_counter()
    if high_mask.any():
        pred[high_mask] = np.clip(MODEL.predict(frame.loc[high_mask, FEATURE_COLUMNS]), 0, None)
    elapsed_ms = int((time.perf_counter() - start) * 1000)
    if medium_mask.any():
        pred[medium_mask] = frame.loc[medium_mask, "qty_rolling_7d"].fillna(0).to_numpy(dtype=float)
    low_mask = ~(high_mask | medium_mask)
    if low_mask.any():
        pred[low_mask] = frame.loc[low_mask, "qty_rolling_28d"].fillna(0).to_numpy(dtype=float)
    return np.clip(pred, 0, None), elapsed_ms


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "model_version": MODEL_VERSION,
        "gate_passed": bool(METADATA.get("gate_passed", False)),
    }


@app.post("/predict")
def predict(payload: dict[str, Any]) -> dict[str, Any]:
    instances = payload.get("instances")
    if not isinstance(instances, list) or not instances:
        raise HTTPException(status_code=400, detail="payload.instances must be a non-empty list")
    frame = pd.DataFrame(instances)
    missing = sorted(set(FEATURE_COLUMNS) - set(frame.columns))
    if missing:
        raise HTTPException(status_code=400, detail=f"missing feature columns: {missing}")
    pred, inference_ms = _predict_policy(frame)
    predictions = [
        {
            "predicted_demand": round(float(value), 4),
            "confidence_low": round(float(max(value * 0.75, 0)), 4),
            "confidence_high": round(float(value * 1.25), 4),
            "model_version": MODEL_VERSION,
            "inference_ms": inference_ms,
        }
        for value in pred
    ]
    return {"predictions": predictions}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
