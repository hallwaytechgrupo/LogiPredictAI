import json

import pandas as pd
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from logipredict.demo import generate
from logipredict.prepare import haversine, prepare
from logipredict.schema import FEATURES, Shipment, feature_frame
from logipredict.service import create_app
from logipredict.train import temporal_split, train


@pytest.fixture
def shipment():
    return {"purchase_at": "2018-01-01T10:00:00", "dispatched_at": "2018-01-02T12:00:00",
            "estimated_delivery_at": "2018-01-10T00:00:00", "seller_state": "SP", "customer_state": "RJ",
            "distance_km": None, "total_weight_g": None, "total_volume_cm3": None,
            "items_count": 1, "sellers_count": 1, "price": 100, "freight_value": 20}


def write_raw(root):
    tables = {
        "orders": [{"order_id": "o1", "customer_id": "c1", "order_status": "delivered",
                    "order_purchase_timestamp": "2018-01-01 10:00:00",
                    "order_delivered_carrier_date": "2018-01-02 12:00:00",
                    "order_delivered_customer_date": "2018-01-10 23:59:59",
                    "order_estimated_delivery_date": "2018-01-10 00:00:00"}],
        "customers": [{"customer_id": "c1", "customer_zip_code_prefix": "01234", "customer_state": "SP"}],
        "sellers": [{"seller_id": "s1", "seller_zip_code_prefix": "01234", "seller_state": "SP"}],
        "products": [{"product_id": "p1", "product_weight_g": 500, "product_length_cm": 10,
                      "product_width_cm": 5, "product_height_cm": 2}],
        "order_items": [{"order_id": "o1", "order_item_id": i, "product_id": "p1", "seller_id": "s1",
                         "price": 25, "freight_value": 5} for i in [1, 2]],
        "geolocation": [{"geolocation_zip_code_prefix": "01234", "geolocation_lat": lat,
                         "geolocation_lng": -46.6} for lat in [-23.5, -23.6]],
    }
    for name, rows in tables.items():
        pd.DataFrame(rows).to_csv(root / f"olist_{name}_dataset.csv", index=False)


def test_prepare_preserves_order_grain_and_calendar_deadline(tmp_path):
    write_raw(tmp_path)
    frame, quality = prepare(tmp_path)
    assert len(frame) == 1  # Dois itens e duas coordenadas não produzem quatro pedidos.
    row = frame.iloc[0]
    assert row.items_count == 2
    assert row.total_weight_g == 1000
    assert row.total_volume_cm3 == 200
    assert row.price == 50
    assert row.freight_value == 10
    assert row.is_late == 0  # Entregar à noite no dia prometido não é atraso.
    assert row.distance_km == pytest.approx(0)
    assert quality["retained_orders"] == 1


def test_prepare_unknown_weight_not_silently_zero(tmp_path):
    write_raw(tmp_path)
    path = tmp_path / "olist_products_dataset.csv"
    products = pd.read_csv(path)
    products["product_weight_g"] = None
    products.to_csv(path, index=False)
    frame, quality = prepare(tmp_path)
    assert pd.isna(frame.total_weight_g.iloc[0])
    assert quality["missing_features"]["total_weight_g"] == 1


def test_prepare_rejects_conflicting_key(tmp_path):
    write_raw(tmp_path)
    path = tmp_path / "olist_customers_dataset.csv"
    customers = pd.read_csv(path)
    pd.concat([customers, customers.assign(customer_state="RJ")]).to_csv(path, index=False)
    with pytest.raises(ValueError, match="conflitantes"):
        prepare(tmp_path)


def test_distance_known_route():
    assert haversine(-23.5505, -46.6333, -22.9068, -43.1729) == pytest.approx(360.7, abs=2)


def test_temporal_split_purges_future_labels():
    frame = generate()
    training, validation, test = temporal_split(frame)
    assert training.dispatched_at.max() < validation.dispatched_at.min()
    assert training.delivered_at.max() < validation.dispatched_at.min()
    assert validation.dispatched_at.max() < test.dispatched_at.min()
    assert validation.delivered_at.max() < test.dispatched_at.min()
    assert not set(training.order_id) & set(test.order_id)
    assert "delivered_at" not in FEATURES
    assert "is_late" not in FEATURES


@pytest.mark.parametrize("patch", [
    {"customer_state": "XX"}, {"price": -1}, {"price": True}, {"price": "100"},
    {"total_weight_g": float("inf")},
    {"items_count": 1.5}, {"sellers_count": 2}, {"dispatched_at": "2017-01-01T00:00:00"},
    {"purchase_at": "2018-01-01T10:00:00Z"}, {"delivered_at": "2018-01-11T00:00:00"},
])
def test_input_rejects_invalid_or_leaked_data(shipment, patch):
    with pytest.raises(ValidationError):
        Shipment.model_validate({**shipment, **patch})


def test_shared_features(shipment):
    row = Shipment.model_validate(shipment)
    features = feature_frame(pd.DataFrame([row.model_dump()]))
    assert list(features.columns) == FEATURES
    assert features.remaining_days.iloc[0] == 8
    assert features.dispatch_lead_days.iloc[0] == pytest.approx(26 / 24)


def test_missing_model_explicitly_unavailable(tmp_path, shipment):
    with TestClient(create_app(tmp_path)) as client:
        assert client.get("/health").status_code == 503
        assert client.post("/predict", json=shipment).status_code == 503


def test_training_artifact_serves_predictions(tmp_path, shipment):
    path = tmp_path / "demo.csv"
    generate().to_csv(path, index=False)
    metadata = train(path, tmp_path / "model", tmp_path / "reports", "synthetic", trees=15)
    assert metadata["synthetic"] is True
    assert metadata["test"]["average_precision"] > metadata["baseline_test"]["average_precision"]
    with TestClient(create_app(tmp_path / "model")) as client:
        assert client.get("/health").status_code == 200
        response = client.post("/predict", json=shipment)
        assert response.status_code == 200
        result = response.json()
        assert 0 <= result["delay_probability"] <= 1
        assert result["predicted_late"] == (result["delay_probability"] >= result["threshold"])
        assert result["synthetic"] is True
        assert len(result["warnings"]) == 3
        assert client.get("/analytics/states").json()["type"] == "historical_observed"
        assert client.post("/predict", json={**shipment, "items_count": -1}).status_code == 422
    report = json.loads((tmp_path / "reports" / "metrics.json").read_text(encoding="utf-8"))
    assert report["dataset_sha256"] == metadata["dataset_sha256"]
