"""Gera estatísticas Olist para o BE-03, reutilizando o ETL existente."""
import argparse
import hashlib
import json
from pathlib import Path
from tempfile import NamedTemporaryFile

import numpy as np
import pandas as pd

from .prepare import REQUIRED, prepare

BACK_DIR = Path(__file__).resolve().parents[2]
DISTANCE_BOUNDS_KM = [250, 750, 1500]
WEIGHT_BOUNDS_G = [1000, 5000]
MIN_SAMPLE_SIZE = 100
# Corte anterior à validação e ao teste temporal do experimento ML existente.
OBSERVED_BEFORE = "2018-03-01"


def summarize(rows):
    """Resume tempos em dias de calendário, com percentis observados."""
    return {
        "sample_size": len(rows),
        "transit_days_p50": int(rows.transit_days.quantile(0.5, interpolation="higher")),
        "transit_days_p90": int(rows.transit_days.quantile(0.9, interpolation="higher")),
        "weight_g_min": float(rows.total_weight_g.min()),
        "weight_g_max": float(rows.total_weight_g.max()),
        "distance_km_min": float(rows.distance_km.min()),
        "distance_km_max": float(rows.distance_km.max()),
    }


def build_reference(raw_dir):
    """Agrega registros reais completos, cujas entregas já ocorreram no corte."""
    source_files = {}
    for table in REQUIRED:
        filename = f"olist_{table}_dataset.csv"
        with (raw_dir / filename).open("rb") as source_file:
            source_files[filename] = hashlib.file_digest(source_file, "sha256").hexdigest()

    orders, quality = prepare(raw_dir)
    observed = orders[orders.delivered_at < pd.Timestamp(OBSERVED_BEFORE)].copy()
    complete = (
        np.isfinite(observed.total_weight_g) & observed.total_weight_g.gt(0)
        & np.isfinite(observed.distance_km) & observed.distance_km.between(0, 20050)
    )
    rows = observed.loc[complete].copy()
    if len(rows) < MIN_SAMPLE_SIZE:
        raise ValueError(f"São necessários pelo menos {MIN_SAMPLE_SIZE} pedidos completos antes do corte.")

    rows["transit_days"] = (rows.delivered_at.dt.normalize() - rows.dispatched_at.dt.normalize()).dt.days
    # searchsorted(side='left') mantém o limite superior dentro da faixa.
    rows["distance_band"] = np.searchsorted(DISTANCE_BOUNDS_KM, rows.distance_km, side="left")
    rows["weight_band"] = np.searchsorted(WEIGHT_BOUNDS_G, rows.total_weight_g, side="left")
    groups = []
    for (distance_band, weight_band), group in rows.groupby(["distance_band", "weight_band"], sort=True):
        groups.append({"distance_band": int(distance_band), "weight_band": int(weight_band), **summarize(group)})
    distance_groups = [
        {"distance_band": int(band), **summarize(group)}
        for band, group in rows.groupby("distance_band", sort=True)
    ]
    reference = {
        "schema_version": 1,
        "method": "historical_rules",
        "source": "olist",
        "synthetic": False,
        "dataset_url": "https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce",
        "source_files_sha256": source_files,
        "observed_before": OBSERVED_BEFORE,
        "period": {
            "dispatch_min": str(rows.dispatched_at.min()),
            "dispatch_max": str(rows.dispatched_at.max()),
            "delivery_min": str(rows.delivered_at.min()),
            "delivery_max": str(rows.delivered_at.max()),
        },
        "quality": {
            "raw_orders": quality["input_orders"],
            "eligible_orders": quality["retained_orders"],
            "observed_orders_before_cutoff": len(observed),
            "excluded_incomplete_weight_or_distance": int((~complete).sum()),
            "reference_orders": len(rows),
        },
        "policy": {
            "distance_bounds_km": DISTANCE_BOUNDS_KM,
            "weight_bounds_g": WEIGHT_BOUNDS_G,
            "min_sample_size": MIN_SAMPLE_SIZE,
            "quantile_interpolation": "higher",
            "high": "remaining_days < transit_days_p50",
            "medium": "transit_days_p50 <= remaining_days < transit_days_p90",
            "low": "remaining_days >= transit_days_p90",
        },
        "global": summarize(rows),
        "distance_groups": distance_groups,
        "groups": groups,
    }
    digest = hashlib.sha256(json.dumps(reference, sort_keys=True).encode()).hexdigest()
    reference["rules_version"] = f"be03-olist-v1-{digest[:12]}"
    return reference


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, default=BACK_DIR / "data" / "raw")
    parser.add_argument("--output", type=Path, default=BACK_DIR / "src" / "data" / "predict-reference.json")
    args = parser.parse_args()
    reference = build_reference(args.raw_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(dir=args.output.parent, suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
    try:
        temporary.write_text(
            json.dumps(reference, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8",
        )
        temporary.replace(args.output)
    finally:
        temporary.unlink(missing_ok=True)
    print(json.dumps({"rules_version": reference["rules_version"], **reference["quality"]}, indent=2))


if __name__ == "__main__":
    main()
