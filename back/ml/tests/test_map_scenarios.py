"""Verifica o modelo preservado, isolamento temporal e contratos do novo mapa."""

from datetime import date

import numpy as np
import pandas as pd
import pytest
from fastapi.testclient import TestClient
from logipredict.map_scenarios import engine, holiday
from logipredict.service import create_app


@pytest.fixture(scope="module")
def client():
    with TestClient(create_app()) as app:
        yield app


def test_all_historical_predictions_reproduce_preserved_model():
    e = engine()
    # O rótulo observado fica fora do frame de inferência.
    raw = e.rows[list(e.contract.model_fields)]
    assert "atraso_real" not in raw and "delivered_at" not in raw
    score = e.pipeline.predict_proba(raw)[:, 1]
    np.testing.assert_allclose(score, e.rows.score, atol=1e-12, rtol=0)
    alert, late = score >= e.metadata["threshold"], e.rows.atraso_real.eq(1)
    assert (
        int((alert & late).sum()),
        int((alert & ~late).sum()),
        int((~alert & late).sum()),
        int((~alert & ~late).sum()),
    ) == (564, 4358, 140, 14196)


def test_search_combines_filters_and_paginates(client):
    response = client.get(
        "/map/orders",
        params={
            "start_date": "2018-06-01",
            "end_date": "2018-06-30",
            "origin_state": "SP",
            "destination_state": "RJ",
            "region": "Sudeste",
            "risk": "Alto",
            "origin_prefix": "0",
            "limit": 2,
        },
    )
    assert response.status_code == 200
    result = response.json()
    assert sum(result["counts"].values()) == result["total"] > 2
    assert result["counts"]["Alto"] == result["total"]
    for row in result["data"]:
        assert row["risk"] == "Alto"
        assert row["origin"]["state"] == "SP" and row["origin"]["prefix5"].startswith(
            "0"
        )
        assert row["destination"]["state"] == "RJ"
        assert "2018-06-01" <= row["purchase_at"][:10] <= "2018-06-30"
    second = client.get(
        "/map/orders", params={"risk": "Alto", "limit": 2, "offset": 2}
    ).json()
    assert second["offset"] == 2
    assert len(second["data"]) == 2
    assert (
        client.get("/map/orders", params={"order_id": "nao-existe"}).json()["total"]
        == 0
    )


@pytest.mark.parametrize(
    "params",
    [
        {"start_date": "2018-07-02", "end_date": "2018-07-01"},
        {"start_date": "2018-02-30"},
        {"origin_state": "ZZ"},
        {"region": "Inventada"},
        {"risk": "aleatorio"},
        {"origin_prefix": "ABC"},
        {"limit": 10000},
        {"offset": -1},
    ],
)
def test_invalid_filters_are_not_ignored(client, params):
    assert client.get("/map/orders", params=params).status_code == 422


def test_search_risk_bands_reflect_both_stages(client):
    data = client.get("/map/orders").json()
    assert data["counts"] == {"Baixo": 14330, "Médio": 6, "Alto": 4922}
    e = engine()
    assert e.band(e.pipeline.reference_threshold, e.metadata["threshold"]) == "Alto"
    assert (
        e.band(e.pipeline.reference_threshold, e.metadata["threshold"] - 0.001)
        == "Médio"
    )
    assert e.band(e.pipeline.reference_threshold - 0.001, 0.0) == "Baixo"


@pytest.mark.parametrize("band", ["Baixo", "Médio", "Alto"])
def test_live_simulation_matches_saved_prediction_without_changing_model(client, band):
    e = engine()
    row = e.rows[e.rows.risk.eq(band)].iloc[0]
    before = e.pipeline.history_cutoff
    response = client.post("/map/simulate", json={"order_id": row.order_id})
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["model_version"] == "modelo_564_filter"
    assert result["scenario_changed"] is False
    assert result["result"]["risk"] == band
    assert result["result"]["score"] == pytest.approx(row.score, abs=1e-12)
    assert e.pipeline.history_cutoff == before
    assert "atraso_real" not in result["shipment"]
    # Nenhuma alternativa consulta entregas que ocorreram após o cenário base.
    for alternative in result["alternatives"]:
        assert (
            alternative["history"]["history_asof"] <= result["result"]["dispatched_at"]
        )
        assert alternative["purchase_at"] == result["result"]["purchase_at"]


def test_history_excludes_future_completions_even_in_later_alternatives(client):
    e = engine()
    row = e.rows[e.rows.risk.eq("Alto")].iloc[0]
    result = client.post("/map/simulate", json={"order_id": row.order_id}).json()
    raw = result["shipment"]
    when = pd.Timestamp(raw["dispatched_at"])
    events = e.pipeline.history.events
    expected = events[
        (events.delivered_at < when) & events.seller_id.eq(raw["seller_id"])
    ]
    assert result["result"]["history"]["seller_orders"] == len(expected)
    later = [
        a for a in result["alternatives"] if a["dispatched_at"] > raw["dispatched_at"]
    ]
    assert later
    assert all(a["history"]["seller_orders"] == len(expected) for a in later)


def test_real_route_change_uses_real_seller_and_recalculates_distance(client):
    e = engine()
    row = e.rows[e.rows.sellers_count.eq(1)].iloc[0]
    seller = e.sellers[
        e.sellers.prefix5.isin(e.locations.index) & e.sellers.state.eq("PR")
    ].iloc[0]
    target = e.locations[e.locations.state.eq("BA")].iloc[0]
    result = client.post(
        "/map/simulate",
        json={
            "order_id": row.order_id,
            "seller_id": seller.seller_id,
            "destination_prefix5": target.prefix5,
        },
    )
    assert result.status_code == 200, result.text
    data = result.json()
    assert data["shipment"]["seller_id"] == seller.seller_id
    assert (
        data["shipment"]["seller_state"] == "PR"
        and data["shipment"]["customer_state"] == "BA"
    )
    assert data["shipment"]["distance_km"] > 0
    assert data["scenario_changed"]
    assert data["origin"]["prefix5"] == seller.prefix5


def test_holiday_is_calendar_context_and_not_invented_effect(client):
    e = engine()
    row = e.rows[e.rows.sellers_count.eq(1)].iloc[0]
    response = client.post(
        "/map/simulate",
        json={
            "order_id": row.order_id,
            "purchase_at": "2018-09-06T10:00:00",
            "dispatched_at": "2018-09-07T10:00:00",
            "estimated_delivery_at": "2018-09-20T00:00:00",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["calendar"]["dispatch_holiday"] == "Independência do Brasil"
    assert data["calendar"]["model_uses_holidays"] is False
    after = next(
        a
        for a in data["alternatives"]
        if a["label"] == "Despachar após feriado/fim de semana"
    )
    assert after["dispatched_at"].startswith("2018-09-10")
    assert after["estimated_delivery_at"] == data["result"]["estimated_delivery_at"]
    assert after["lower_risk"] == (
        {"Baixo": 0, "Médio": 1, "Alto": 2}[after["risk"]]
        < {"Baixo": 0, "Médio": 1, "Alto": 2}[data["result"]["risk"]]
    )
    assert holiday(date(2018, 11, 20)) is None
    assert holiday(date(2026, 11, 20)) == "Consciência Negra"


def test_rejects_future_label_bad_identity_and_invalid_dates(client):
    e = engine()
    row = e.rows[e.rows.sellers_count.eq(1)].iloc[0]
    for changes in [
        {"delivered_at": "2018-10-01"},
        {"atraso_real": True},
        {"seller_id": "inventado"},
        {"destination_prefix5": "00000"},
        {"total_weight_g": -1},
        {"total_weight_g": True},
        {"dispatched_at": "2017-01-01T00:00:00"},
        {"purchase_at": "2018-12-01T00:00:00"},
        {"dispatched_at": "2018-07-01T00:00:00Z"},
    ]:
        assert (
            client.post(
                "/map/simulate", json={"order_id": row.order_id, **changes}
            ).status_code
            == 422
        )
    assert (
        client.post("/map/simulate", json={"order_id": "desconhecido"}).status_code
        == 404
    )


def test_current_dates_are_marked_as_extrapolation(client):
    row = engine().rows.iloc[0]
    result = client.post(
        "/map/simulate",
        json={
            "order_id": row.order_id,
            "purchase_at": "2026-11-19T10:00:00",
            "dispatched_at": "2026-11-20T10:00:00",
            "estimated_delivery_at": "2026-11-30T00:00:00",
        },
    )
    assert result.status_code == 200
    assert any("não há histórico recente" in w for w in result.json()["warnings"])


def test_catalog_and_sellers_do_not_fabricate_identities(client):
    catalog = client.get("/map/catalog").json()
    assert catalog["metrics"]["TP"] == 564 and catalog["synthetic"] is False
    data = client.get("/map/sellers", params={"q": "SP"}).json()["data"]
    assert data and all(s["seller_id"] in engine().sellers.index for s in data)
    assert (
        client.get("/map/sellers", params={"q": "id-vendedor-inexistente"}).json()[
            "data"
        ]
        == []
    )
