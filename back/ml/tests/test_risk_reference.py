"""Verifica corte temporal, exclusão de ausentes e percentis do BE-03."""
import json
import sys

import pandas as pd
import pytest
from logipredict import build_risk_reference as risk


def test_reference_uses_only_complete_outcomes_before_cutoff(tmp_path, monkeypatch):
    for table in risk.REQUIRED:
        (tmp_path / f"olist_{table}_dataset.csv").write_text("fixture", encoding="utf-8")
    rows = pd.DataFrame({
        "dispatched_at": pd.to_datetime(["2018-01-01"] * 100),
        "delivered_at": pd.to_datetime(["2018-01-04"] * 50 + ["2018-01-10"] * 50),
        "total_weight_g": [500.0] * 100,
        "distance_km": [100.0] * 100,
    })
    excluded = pd.DataFrame({
        "dispatched_at": pd.to_datetime(["2018-02-01"] * 3),
        "delivered_at": pd.to_datetime(["2018-03-01", "2018-02-10", "2018-02-10"]),
        "total_weight_g": [500.0, None, 500.0],
        "distance_km": [100.0, 100.0, None],
    })
    monkeypatch.setattr(risk, "prepare", lambda _: (
        pd.concat([rows, excluded], ignore_index=True), {"input_orders": 103, "retained_orders": 103},
    ))
    reference = risk.build_reference(tmp_path)
    assert reference["quality"]["reference_orders"] == 100
    assert reference["quality"]["excluded_incomplete_weight_or_distance"] == 2
    assert reference["global"]["transit_days_p50"] == 9  # Observação superior no empate.
    assert reference["global"]["transit_days_p90"] == 9
    assert reference["groups"][0]["sample_size"] == 100
    assert reference == risk.build_reference(tmp_path)  # Geração determinística.


def test_reference_rejects_insufficient_observed_history(tmp_path, monkeypatch):
    for table in risk.REQUIRED:
        (tmp_path / f"olist_{table}_dataset.csv").write_text("fixture", encoding="utf-8")
    rows = pd.DataFrame({
        "dispatched_at": pd.to_datetime(["2018-01-01"]),
        "delivered_at": pd.to_datetime(["2018-01-04"]),
        "total_weight_g": [500.0], "distance_km": [100.0],
    })
    monkeypatch.setattr(risk, "prepare", lambda _: (rows, {"input_orders": 1, "retained_orders": 1}))
    with pytest.raises(ValueError, match="100 pedidos"):
        risk.build_reference(tmp_path)


def test_generation_preserves_existing_file_on_failure_and_cleans_temporary_files(tmp_path, monkeypatch):
    output = tmp_path / "reference.json"
    output.write_text("original", encoding="utf-8")
    monkeypatch.setattr(sys, "argv", ["build_risk_reference", "--output", str(output)])
    reference = {"rules_version": "test-only", "quality": {}, "invalid": float("nan")}
    monkeypatch.setattr(risk, "build_reference", lambda _: reference)
    with pytest.raises(ValueError):
        risk.main()
    assert output.read_text(encoding="utf-8") == "original"
    assert list(tmp_path.iterdir()) == [output]
    del reference["invalid"]
    risk.main()
    assert json.loads(output.read_text(encoding="utf-8")) == reference
    assert list(tmp_path.iterdir()) == [output]
