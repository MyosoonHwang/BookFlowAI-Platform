import argparse
import json
import time
from datetime import date
from pathlib import Path

import joblib
import numpy as np
import pandas as pd


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


def load_model(model_dir: Path):
    model_path = model_dir / "model.joblib"
    metrics_path = model_dir / "metrics.json"
    if not model_path.exists():
        raise FileNotFoundError(model_path)
    model = joblib.load(model_path)
    metadata = json.loads(metrics_path.read_text(encoding="utf-8")) if metrics_path.exists() else {}
    if metrics_path.exists() and not metadata.get("gate_passed", False):
        raise RuntimeError(f"Model gate did not pass: {metadata.get('reject_reasons')}")
    return model, metadata


def next_dates(start_date: str, horizon: int) -> list[pd.Timestamp]:
    start = pd.to_datetime(start_date).date()
    return [pd.Timestamp(start + pd.Timedelta(days=offset)) for offset in range(1, horizon + 1)]


def build_future_frame(latest: pd.DataFrame, prediction_date: str, horizon: int) -> pd.DataFrame:
    latest = latest.copy()
    frames = []
    for offset, target_date in enumerate(next_dates(prediction_date, horizon), start=1):
        future = latest.copy()
        future["target_date"] = target_date.date().isoformat()
        future["feature_date"] = target_date.date().isoformat()
        future["day_of_week"] = ((target_date.dayofweek + 1) % 7) + 1
        future["month"] = target_date.month
        future["weekend_flag"] = int(future["day_of_week"].iloc[0] in (1, 7))
        future["holiday_flag"] = 0
        future["event_nearby_days"] = np.maximum(future["event_nearby_days"].fillna(30).astype(float) - offset, 0)
        future["book_age_days"] = future["book_age_days"].fillna(0).astype(float) + offset
        future["days_since_last_stockout"] = future["days_since_last_stockout"].fillna(0).astype(float) + offset
        frames.append(future)
    return pd.concat(frames, ignore_index=True)


def predict_policy(model, frame: pd.DataFrame) -> np.ndarray:
    segment = frame["demand_segment"].fillna("low")
    high_mask = segment.eq("high").to_numpy()
    medium_mask = segment.eq("medium").to_numpy()
    pred = np.zeros(len(frame), dtype=float)
    start = time.perf_counter()
    if high_mask.any():
        pred[high_mask] = np.clip(model.predict(frame.loc[high_mask, FEATURE_COLUMNS]), 0, None)
    elapsed_ms = int((time.perf_counter() - start) * 1000)
    if medium_mask.any():
        pred[medium_mask] = frame.loc[medium_mask, "qty_rolling_7d"].fillna(0).to_numpy(dtype=float)
    low_mask = ~(high_mask | medium_mask)
    if low_mask.any():
        pred[low_mask] = frame.loc[low_mask, "qty_rolling_28d"].fillna(0).to_numpy(dtype=float)
    return np.clip(pred, 0, None), elapsed_ms


def main() -> None:
    parser = argparse.ArgumentParser(description="Create BOOKFLOW D+1..D+N store demand batch forecasts.")
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--latest-features-csv", required=True)
    parser.add_argument("--output-csv", required=True)
    parser.add_argument("--horizon", type=int, default=5)
    parser.add_argument("--prediction-date", default=date.today().isoformat())
    args = parser.parse_args()

    model, metadata = load_model(Path(args.model_dir))
    latest = pd.read_csv(args.latest_features_csv)
    missing = sorted(set(["feature_date", "isbn13"] + FEATURE_COLUMNS) - set(latest.columns))
    if missing:
        raise ValueError(f"Latest features CSV missing required columns: {missing}")

    latest = latest.sort_values(["isbn13", "store_id", "feature_date"]).drop_duplicates(["isbn13", "store_id"], keep="last")
    future = build_future_frame(latest, args.prediction_date, args.horizon)
    pred, inference_ms = predict_policy(model, future)

    model_version = metadata.get("model_version", Path(args.model_dir).name)
    output = pd.DataFrame(
        {
            "prediction_date": args.prediction_date,
            "target_date": future["target_date"],
            "isbn13": future["isbn13"],
            "store_id": future["store_id"].astype(int),
            "predicted_demand": np.round(pred, 4),
            "confidence_low": np.round(np.maximum(pred * 0.75, 0), 4),
            "confidence_high": np.round(pred * 1.25, 4),
            "model_version": model_version,
            "inference_ms": inference_ms,
        }
    )
    output_path = Path(args.output_csv)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(output_path, index=False)
    summary = {
        "prediction_date": args.prediction_date,
        "horizon": args.horizon,
        "rows": int(len(output)),
        "series_count": int(output[["isbn13", "store_id"]].drop_duplicates().shape[0]),
        "min_target_date": str(output["target_date"].min()),
        "max_target_date": str(output["target_date"].max()),
        "predicted_sum": float(output["predicted_demand"].sum()),
        "negative_predictions": int((output["predicted_demand"] < 0).sum()),
        "model_version": model_version,
        "output_csv": str(output_path),
    }
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
