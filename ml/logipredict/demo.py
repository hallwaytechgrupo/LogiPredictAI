"""Gera dados ARTIFICIAIS para verificar a instalação. Não mede desempenho na Olist."""
import argparse
from pathlib import Path

import numpy as np
import pandas as pd


def generate(size=1200, seed=42):
    rng = np.random.default_rng(seed)
    purchase = pd.date_range("2017-01-01", periods=size, freq="6h")
    lead = rng.integers(1, 5, size)
    dispatch = purchase + pd.to_timedelta(lead, unit="D")
    distance = rng.uniform(10, 3500, size)
    transit = np.maximum(1, distance / 190 + rng.normal(2, 3, size))
    promise = rng.integers(9, 26, size)
    frame = pd.DataFrame({
        "order_id": [f"synthetic-{i:05}" for i in range(size)],
        "purchase_at": purchase, "dispatched_at": dispatch,
        "delivered_at": dispatch + pd.to_timedelta(transit, unit="D"),
        "estimated_delivery_at": purchase.normalize() + pd.to_timedelta(promise, unit="D"),
        "seller_state": rng.choice(["SP", "RJ", "MG"], size),
        "customer_state": rng.choice(["SP", "RJ", "MG", "BA", "AM"], size),
        "distance_km": distance, "total_weight_g": rng.uniform(100, 15000, size),
        "total_volume_cm3": rng.uniform(100, 50000, size),
        "items_count": np.ones(size, dtype=int), "sellers_count": np.ones(size, dtype=int),
        "price": rng.uniform(20, 2000, size), "freight_value": rng.uniform(10, 120, size),
    })
    frame["is_late"] = (frame.delivered_at.dt.normalize() > frame.estimated_delivery_at.dt.normalize()).astype(int)
    return frame


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("data/processed/demo.csv"))
    parser.add_argument("--rows", type=int, default=1200)
    args = parser.parse_args()
    if args.rows < 300:
        parser.error("Use ao menos 300 linhas para os três períodos.")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    generate(args.rows).to_csv(args.output, index=False)
    print(f"DADOS SINTÉTICOS: {args.output}; não representam a base Olist.")


if __name__ == "__main__":
    main()
