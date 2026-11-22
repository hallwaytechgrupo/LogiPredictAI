"""Pesquisa retrospectiva e cenários com o modelo 564 + filtro preservado.

O simulador usa os pesos originais. O histórico de cada cenário contém somente
entregas conhecidas no instante de consulta; alternativas não recebem o futuro.
"""

import hashlib
import json
import logging
import sys
import unicodedata
from datetime import date, datetime, timedelta
from functools import lru_cache
from pathlib import Path
from threading import Lock
from typing import Annotated, Literal

import joblib
import numpy as np
import pandas as pd
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, ValidationError

FINAL = (Path(__file__).resolve().parent / "../../../ML/modelos_finais").resolve()
CATALOG = Path(__file__).resolve().parents[1] / "map_data"
NAME = "Modelo_564_atrasos_4358_falsos_alertas_140_perdidos"
RANK = {"Baixo": 0, "Médio": 1, "Alto": 2}
REGIONS = {
    **dict.fromkeys(["AC", "AP", "AM", "PA", "RO", "RR", "TO"], "Norte"),
    **dict.fromkeys(["AL", "BA", "CE", "MA", "PB", "PE", "PI", "RN", "SE"], "Nordeste"),
    **dict.fromkeys(["DF", "GO", "MT", "MS"], "Centro-Oeste"),
    **dict.fromkeys(["ES", "MG", "RJ", "SP"], "Sudeste"),
    **dict.fromkeys(["PR", "RS", "SC"], "Sul"),
}
router = APIRouter(prefix="/map", tags=["Mapa e cenários"])
logger = logging.getLogger(__name__)
_model_lock = Lock()
_catalog_lock = Lock()
MODEL_LIMITATIONS = [
    "Score não calibrado: não é uma porcentagem de chance de atraso.",
    "Base histórica Olist de 2016–2018; não representa a operação atual.",
    "Resultado retrospectivo exploratório; o período final foi consultado em pesquisas anteriores.",
    "564 atrasos encontrados incluem 130 já vencidos no despacho e 434 antecipados.",
    "O modelo não usa feriados explicitamente nem identifica causas de atraso.",
]


def verify(root, manifest):
    for relative, expected in manifest.items():
        if hashlib.sha256((root / relative).read_bytes()).hexdigest() != expected:
            raise ValueError(f"Integridade inválida: {relative}")


class MapEngine:
    def __init__(self):
        sys.path.insert(0, str(FINAL / "codigo"))
        from context_risk.contract import ContextShipment
        from context_risk.runtime import meta_frame, reference_score

        self.contract, self.meta_frame, self.reference_score = (
            ContextShipment,
            meta_frame,
            reference_score,
        )
        integrity = json.loads(
            (FINAL / "artefatos/integridade.json").read_text(encoding="utf-8")
        )
        verify(FINAL, integrity)
        self.bundle = joblib.load(FINAL / "artefatos" / f"{NAME}.joblib")
        self.pipeline, self.metadata = self.bundle["pipeline"], self.bundle["metadata"]
        self._rows = None
        self._rows_lock = Lock()
        self.locations, self.sellers, self.location_terms = geographic_catalog()

    @property
    def rows(self):
        # A avaliação retrospectiva só é carregada pelas rotas de pesquisa antiga.
        with self._rows_lock:
            if self._rows is None:
                self._rows = self._load_rows()
            return self._rows

    def _load_rows(self):
        rows = pd.read_csv(
            FINAL / "dados/pedidos_avaliacao.csv.gz",
            dtype={"origin_prefix5": str, "destination_prefix5": str},
        )
        predictions = pd.read_csv(FINAL / "dados/previsoes_564.csv")
        if not rows.order_id.equals(predictions.order_id):
            raise ValueError("O relatório de previsões não corresponde à base final.")
        rows["score"] = predictions.score
        rows["base_score"] = self.reference_score(self.pipeline.reference, rows)
        rows["risk"] = [self.band(b, p) for b, p in zip(rows.base_score, rows.score)]
        return rows.set_index("order_id", drop=False).rename_axis(None)

    def band(self, base, score):
        if score >= self.metadata["threshold"]:
            return "Alto"
        return "Médio" if base >= self.pipeline.reference_threshold else "Baixo"

    def place(self, prefix, state=None):
        if prefix not in self.locations.index:
            return None
        row = self.locations.loc[prefix].to_dict()
        row["state"] = state or row["state"]
        row["region"] = REGIONS[row["state"]]
        return row

    def shipment(self, order_id):
        if order_id not in self.rows.index:
            raise HTTPException(
                404, "Pedido não encontrado na amostra histórica do mapa."
            )
        row = self.rows.loc[order_id]
        fields = self.contract.model_fields
        raw = {k: (None if pd.isna(row[k]) else row[k]) for k in fields}
        for key in ["items_count", "sellers_count"]:
            raw[key] = int(raw[key])
        return self.contract.model_validate(raw).model_dump()

    def summary(self, row):
        return {
            "order_id": row.order_id,
            "purchase_at": row.purchase_at,
            "dispatched_at": row.dispatched_at,
            "estimated_delivery_at": row.estimated_delivery_at,
            "origin": self.place(row.origin_prefix5, row.seller_state),
            "destination": self.place(row.destination_prefix5, row.customer_state),
            "risk": row.risk,
            "score": float(row.score),
            "already_overdue": row.estimated_delivery_at[:10] < row.dispatched_at[:10],
        }

    def evaluate(self, shipments, asof):
        """Replica o pipeline final e expõe suas duas decisões para a interface.

        O corte causal é local à chamada. Não altera o modelo compartilhado.
        """
        frame = pd.DataFrame(shipments)
        p = self.pipeline
        base = self.reference_score(p.reference, frame)
        context = p.history.query(frame, cutoff=asof)
        reviewed = p.reviewer.predict_proba(
            self.meta_frame(frame, base, p.reference_threshold, context)
        )[:, 1]
        gate = base >= p.reference_threshold
        overdue = (
            pd.to_datetime(frame.estimated_delivery_at).dt.normalize()
            < pd.to_datetime(frame.dispatched_at).dt.normalize()
        ).to_numpy()
        score = np.where(gate, np.where(overdue, 1.0, reviewed), 0.0)
        results = []
        for i, raw in enumerate(shipments):
            remaining = (
                raw["estimated_delivery_at"].date() - raw["dispatched_at"].date()
            ).days
            history = context.iloc[i]
            results.append(
                {
                    "risk": self.band(base[i], score[i]),
                    "score": float(score[i]),
                    "base_score": float(base[i]),
                    "base_threshold": float(p.reference_threshold),
                    "filter_score": float(reviewed[i]),
                    "threshold": float(self.metadata["threshold"]),
                    "predicted_late": bool(score[i] >= self.metadata["threshold"]),
                    "first_stage_alert": bool(gate[i]),
                    "already_overdue": bool(overdue[i]),
                    "remaining_days": remaining,
                    "history": {
                        "seller_orders": int(history.h_seller_count),
                        "route_orders": int(history.h_route_count),
                        "history_asof": min(raw["dispatched_at"], asof).isoformat(),
                    },
                    "purchase_at": raw["purchase_at"].isoformat(),
                    "dispatched_at": raw["dispatched_at"].isoformat(),
                    "estimated_delivery_at": raw["estimated_delivery_at"].isoformat(),
                }
            )
        return results


@lru_cache(maxsize=1)
def _load_engine():
    return MapEngine()


def engine():
    # Duas requisições simultâneas não devem carregar duas cópias dos pesos.
    with _model_lock:
        return _load_engine()


@lru_cache(maxsize=1)
def _load_geographic_catalog():
    manifest = json.loads((CATALOG / "manifest.json").read_text(encoding="utf-8"))
    verify(CATALOG, manifest["sha256"])
    places = pd.read_csv(
        CATALOG / "locations.csv.gz", dtype={"prefix5": str}
    ).set_index("prefix5", drop=False)
    sellers = pd.read_csv(CATALOG / "sellers.csv.gz", dtype={"prefix5": str}).set_index(
        "seller_id", drop=False
    )
    terms = places[["prefix5", "city", "state"]].agg(" ".join, axis=1).map(search_text)
    return places, sellers, terms


def geographic_catalog():
    with _catalog_lock:
        return _load_geographic_catalog()


def ready():
    try:
        return engine()
    except (OSError, ValueError, ImportError):
        logger.exception("Não foi possível carregar os artefatos finais do mapa")
        raise HTTPException(
            503,
            "Modelo 564 ou catálogo real ausente/incompatível. Confira a instalação do mapa.",
        ) from None


@router.get("/catalog")
def catalog():
    e = ready()
    return {
        "model_version": e.metadata["version"],
        "source": "olist",
        "synthetic": False,
        "metrics": e.metadata["metrics"],
        "total": len(e.rows),
        "start_date": e.rows.purchase_at.min()[:10],
        "end_date": e.rows.purchase_at.max()[:10],
        "states": sorted(REGIONS),
        "regions": sorted(set(REGIONS.values())),
        "history_end": str(e.pipeline.history.events.delivered_at.max()),
        "risk_definitions": {
            "Baixo": "A primeira etapa não gerou alerta.",
            "Médio": "A primeira etapa alertou, mas o filtro de contexto retirou o alerta.",
            "Alto": "O modelo final manteve o alerta de atraso.",
        },
        "limitations": MODEL_LIMITATIONS,
    }


@router.get("/orders")
def search(
    start_date: date | None = None,
    end_date: date | None = None,
    origin_state: str | None = None,
    destination_state: str | None = None,
    region: str | None = None,
    risk: Literal["Baixo", "Médio", "Alto"] | None = None,
    origin_prefix: Annotated[str, Query(pattern=r"^\d{1,5}$")] | None = None,
    destination_prefix: Annotated[str, Query(pattern=r"^\d{1,5}$")] | None = None,
    order_id: Annotated[str, Query(max_length=64)] | None = None,
    offset: Annotated[int, Query(ge=0, le=20000)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
):
    e = ready()
    if start_date and end_date and start_date > end_date:
        raise HTTPException(422, "A data inicial deve ser anterior ou igual à final.")
    if any(
        uf is not None and uf not in REGIONS for uf in [origin_state, destination_state]
    ):
        raise HTTPException(422, "UF inválida.")
    if region is not None and region not in REGIONS.values():
        raise HTTPException(422, "Região inválida.")
    rows = e.rows
    days = rows.purchase_at.str[:10]
    mask = pd.Series(True, index=rows.index)
    if start_date:
        mask &= days >= start_date.isoformat()
    if end_date:
        mask &= days <= end_date.isoformat()
    for column, value in [
        ("seller_state", origin_state),
        ("customer_state", destination_state),
        ("risk", risk),
    ]:
        if value is not None:
            mask &= rows[column].eq(value)
    if region is not None:
        mask &= rows.customer_state.map(REGIONS).eq(region)
    if origin_prefix:
        mask &= rows.origin_prefix5.str.startswith(origin_prefix)
    if destination_prefix:
        mask &= rows.destination_prefix5.str.startswith(destination_prefix)
    if order_id:
        mask &= rows.order_id.str.contains(order_id.strip(), regex=False)
    filtered = rows[mask]
    counts = {band: int(filtered.risk.eq(band).sum()) for band in RANK}
    page = filtered.sort_values(["purchase_at", "order_id"]).iloc[
        offset : offset + limit
    ]
    return {
        "total": len(filtered),
        "offset": offset,
        "limit": limit,
        "counts": counts,
        "model_version": e.metadata["version"],
        "prediction_mode": "saved_retrospective_predictions",
        "data": [e.summary(row) for row in page.itertuples()],
    }


@router.get("/order")
def order(order_id: Annotated[str, Query(min_length=1, max_length=64)]):
    e = ready()
    shipment = e.shipment(order_id)
    row = e.rows.loc[order_id]
    return {
        **e.summary(row),
        "shipment": shipment,
        "observed_late": bool(row.atraso_real),
        "observed_result_usage": "Apenas conferência posterior; nunca entrada do modelo.",
    }


@router.get("/sellers")
def sellers(q: Annotated[str, Query(max_length=128)] = ""):
    e = ready()
    rows = e.sellers
    terms = (
        rows[["seller_id", "prefix5", "state", "city"]]
        .agg(" ".join, axis=1)
        .str.casefold()
    )
    rows = rows[terms.str.contains(q.strip().casefold(), regex=False)].head(30)
    return {"data": rows.to_dict(orient="records")}


def search_text(value):
    return "".join(
        c
        for c in unicodedata.normalize("NFKD", value.casefold())
        if not unicodedata.combining(c)
    )


@router.get("/locations")
def locations(q: Annotated[str, Query(min_length=2, max_length=128)]):
    # A busca de CEPs não carrega o modelo nem calcula previsões de pedidos antigos.
    try:
        places, _, terms = geographic_catalog()
    except (OSError, ValueError):
        raise HTTPException(503, "Catálogo de CEPs indisponível.") from None
    term = search_text(q.strip())
    digits = term.replace("-", "")
    if digits.isdigit():
        selected = places[places.prefix5.str.startswith(digits[:5])]
    else:
        # Todos os termos devem aparecer: permite, por exemplo, "sao paulo SP".
        mask = pd.Series(True, index=places.index)
        for word in term.split():
            mask &= terms.str.contains(word, regex=False)
        selected = places[mask]
    return {"data": selected.head(25).to_dict(orient="records")}


def holiday(day):
    # Subconjunto explícito: apenas feriados nacionais de data fixa.
    # Consciência Negra tornou-se nacional após a Lei 14.759/2023.
    fixed = {
        (1, 1): "Confraternização Universal",
        (4, 21): "Tiradentes",
        (5, 1): "Dia do Trabalho",
        (9, 7): "Independência do Brasil",
        (10, 12): "Nossa Senhora Aparecida",
        (11, 2): "Finados",
        (11, 15): "Proclamação da República",
        (12, 25): "Natal",
    }
    if day.year >= 2024:
        fixed[(11, 20)] = "Consciência Negra"
    return fixed.get((day.month, day.day))


def calendar_context(shipment):
    start, end = (
        shipment["dispatched_at"].date(),
        shipment["estimated_delivery_at"].date(),
    )
    holidays = [
        {
            "date": (start + timedelta(days=i)).isoformat(),
            "name": holiday(start + timedelta(days=i)),
        }
        for i in range(max(0, (end - start).days) + 1)
        if holiday(start + timedelta(days=i))
    ]
    return {
        "fixed_national_holidays": holidays,
        "dispatch_holiday": holiday(start),
        "dispatch_weekend": start.weekday() >= 5,
        "coverage": "Somente feriados nacionais de data fixa; não inclui feriados móveis, estaduais, municipais ou pontos facultativos.",
        "model_uses_holidays": False,
    }


class Scenario(BaseModel):
    model_config = ConfigDict(extra="forbid")
    order_id: Annotated[str, Field(min_length=1, max_length=64)]
    purchase_at: datetime | None = None
    dispatched_at: datetime | None = None
    estimated_delivery_at: datetime | None = None
    seller_id: Annotated[str, Field(min_length=1, max_length=128)] | None = None
    destination_prefix5: Annotated[str, Field(pattern=r"^\d{5}$")] | None = None
    total_weight_g: (
        Annotated[float, Field(strict=True, ge=0, le=100000000, allow_inf_nan=False)]
        | None
    ) = None
    total_volume_cm3: (
        Annotated[float, Field(strict=True, ge=0, le=1000000000, allow_inf_nan=False)]
        | None
    ) = None
    price: (
        Annotated[float, Field(strict=True, ge=0, le=100000000, allow_inf_nan=False)]
        | None
    ) = None
    freight_value: (
        Annotated[float, Field(strict=True, ge=0, le=100000000, allow_inf_nan=False)]
        | None
    ) = None


class FutureScenario(BaseModel):
    """Entrada completa de um pedido hipotético, sem reutilizar um pedido antigo."""

    model_config = ConfigDict(extra="forbid")
    purchase_at: datetime
    dispatched_at: datetime
    estimated_delivery_at: datetime
    origin_prefix5: Annotated[str, Field(pattern=r"^\d{5}$")]
    destination_prefix5: Annotated[str, Field(pattern=r"^\d{5}$")]
    seller_id: Annotated[str, Field(min_length=1, max_length=128)] | None = None
    total_weight_g: Annotated[
        float, Field(strict=True, ge=0, le=100000000, allow_inf_nan=False)
    ]
    total_volume_cm3: (
        Annotated[float, Field(strict=True, ge=0, le=1000000000, allow_inf_nan=False)]
        | None
    ) = None
    items_count: Annotated[int, Field(strict=True, ge=1, le=10000)] = 1
    price: Annotated[float, Field(strict=True, ge=0, le=100000000, allow_inf_nan=False)]
    freight_value: Annotated[
        float, Field(strict=True, ge=0, le=100000000, allow_inf_nan=False)
    ]


@router.post("/forecast")
def forecast(request: FutureScenario):
    e = ready()
    origin, destination = (
        e.place(request.origin_prefix5),
        e.place(request.destination_prefix5),
    )
    if origin is None or destination is None:
        raise HTTPException(
            422,
            "Origem ou destino sem coordenadas na base. Pesquise e selecione um CEP disponível.",
        )
    if request.seller_id is not None:
        if request.seller_id not in e.sellers.index:
            raise HTTPException(
                422,
                "Vendedor não encontrado; deixe o campo vazio se não conhece o identificador.",
            )
        seller = e.sellers.loc[request.seller_id]
        if seller.prefix5 != request.origin_prefix5:
            raise HTTPException(
                422, "O vendedor informado não corresponde ao CEP de origem."
            )
        origin["state"] = seller.state
    from logipredict_final.data import haversine

    values = request.model_dump()
    values.update(
        seller_state=origin["state"],
        customer_state=destination["state"],
        sellers_count=1,
        distance_km=float(
            haversine(
                origin["latitude"],
                origin["longitude"],
                destination["latitude"],
                destination["longitude"],
            )
        ),
    )
    raw = validated_shipment(e, values)
    result = analyze(e, raw)
    result.update(
        scenario_type="future_order",
        history_last_delivery=str(e.pipeline.history.events.delivered_at.max()),
    )
    if request.seller_id is None:
        result["warnings"].append(
            "Sem identificador do vendedor: o modelo usa histórico da rota e da região, sem atribuir o histórico de outro vendedor."
        )
    return result


def validated_shipment(e, values):
    try:
        return e.contract.model_validate(values).model_dump()
    except ValidationError as exc:
        raise HTTPException(
            422,
            [
                {
                    "loc": ["body", *item["loc"]],
                    "msg": item["msg"],
                    "type": item["type"],
                }
                for item in exc.errors()
            ],
        ) from None


@router.post("/simulate")
def simulate(request: Scenario):
    e = ready()
    raw = e.shipment(request.order_id)
    original = raw.copy()
    changes = request.model_dump(exclude_none=True, exclude={"order_id"})
    new_seller = changes.pop("seller_id", raw["seller_id"])
    new_destination = changes.get("destination_prefix5", raw["destination_prefix5"])
    changed_route = (
        new_seller != raw["seller_id"] or new_destination != raw["destination_prefix5"]
    )
    if changed_route:
        if raw["sellers_count"] != 1:
            raise HTTPException(
                422, "Para mudar a rota, selecione um pedido com um único vendedor."
            )
        if (
            new_seller not in e.sellers.index
            or new_destination not in e.locations.index
        ):
            raise HTTPException(
                422,
                "Selecione um vendedor e um prefixo de destino existentes no catálogo Olist.",
            )
        seller = e.sellers.loc[new_seller]
        origin, dest = e.place(seller.prefix5, seller.state), e.place(new_destination)
        if origin is None:
            raise HTTPException(
                422, "O vendedor não possui coordenadas conhecidas na base Olist."
            )
        from logipredict_final.data import haversine

        changes.update(
            seller_id=new_seller,
            origin_prefix5=seller.prefix5,
            seller_state=seller.state,
            customer_state=dest["state"],
            distance_km=float(
                haversine(
                    origin["latitude"],
                    origin["longitude"],
                    dest["latitude"],
                    dest["longitude"],
                )
            ),
        )
    raw.update(changes)
    raw = validated_shipment(e, raw)
    return {
        **analyze(e, raw),
        "order_id": request.order_id,
        "scenario_changed": raw != original,
    }


def analyze(e, raw):
    start, dispatch, end = (
        raw[k] for k in ["purchase_at", "dispatched_at", "estimated_delivery_at"]
    )
    if (
        any(not 2016 <= d.year <= 2035 for d in [start, dispatch, end])
        or (end - start).days > 365
    ):
        raise HTTPException(
            422, "Use datas de 2016 a 2035, com até 365 dias entre compra e prazo."
        )
    trained_asof = pd.Timestamp(e.metadata["trained_asof"]).to_pydatetime()
    if dispatch < trained_asof:
        raise HTTPException(
            422,
            f"O modelo já estava treinado a partir de {trained_asof.isoformat()}; escolha um despacho posterior.",
        )
    variants = [("Cenário informado", raw)]
    for days, label in [(-1, "Despachar um dia antes"), (1, "Despachar um dia depois")]:
        candidate = {**raw, "dispatched_at": dispatch + timedelta(days=days)}
        if candidate["dispatched_at"] >= max(start, trained_asof):
            variants.append((label, candidate))
    next_work = dispatch
    for offset in range(3):
        possible = dispatch + timedelta(days=offset)
        if holiday(possible.date()):
            next_work = possible
            break
    while holiday(next_work.date()) or next_work.weekday() >= 5:
        next_work += timedelta(days=1)
    if next_work != dispatch and next_work != dispatch + timedelta(days=1):
        variants.append(
            (
                "Despachar após feriado/fim de semana",
                {**raw, "dispatched_at": next_work},
            )
        )
    # Renegociação muda a promessa, não acelera a entrega física.
    variants.append(
        (
            "Prazo +2 dias (exige acordo com o cliente)",
            {**raw, "estimated_delivery_at": end + timedelta(days=2)},
        )
    )
    evaluated = e.evaluate([v for _, v in variants], asof=dispatch)
    base = evaluated[0]
    alternatives = [
        {
            "label": label,
            **result,
            "lower_risk": RANK[result["risk"]] < RANK[base["risk"]],
            "calendar": calendar_context(v),
        }
        for (label, v), result in zip(variants[1:], evaluated[1:])
    ]
    suggestions = []
    if calendar_context(raw)["fixed_national_holidays"]:
        suggestions.append(
            "Há feriado nacional no intervalo. Confirme o funcionamento do vendedor e do transporte antes de combinar as datas."
        )
    if base["already_overdue"]:
        suggestions.append(
            "O prazo já estava vencido no despacho informado; priorize o contato com o cliente."
        )
    if any(a["lower_risk"] for a in alternatives):
        suggestions.extend(
            f"Comparação: {a['label']} mudou a classificação de {base['risk']} para {a['risk']}."
            for a in alternatives
            if a["lower_risk"]
        )
    else:
        suggestions.append(
            "As alternativas testadas não reduziram a faixa de risco. Acompanhe o pedido e confirme a capacidade de entrega."
        )
    warnings = list(MODEL_LIMITATIONS)
    if dispatch > e.pipeline.history.events.delivered_at.max().to_pydatetime():
        warnings.append(
            "Data posterior à base Olist: não há histórico recente para essa operação; cenário apenas exploratório."
        )
    if raw["sellers_count"] > 1:
        warnings.append(
            "Pedido com vários vendedores: histórico do vendedor principal e distância agregada; o mapa não individualiza pacotes."
        )
    if any(
        raw[k] is None for k in ["distance_km", "total_weight_g", "total_volume_cm3"]
    ):
        warnings.append(
            "Medidas ausentes são preenchidas com estatísticas do treinamento."
        )
    return {
        "model_version": e.metadata["version"],
        "source": "olist",
        "synthetic": False,
        "shipment": raw,
        "origin": e.place(raw["origin_prefix5"], raw["seller_state"]),
        "destination": e.place(raw["destination_prefix5"], raw["customer_state"]),
        "result": base,
        "calendar": calendar_context(raw),
        "alternatives": alternatives,
        "suggestions": suggestions,
        "warnings": warnings,
        "comparison_policy": "Compra e prazo permanecem fixos nas alternativas de despacho; o histórico é congelado no despacho informado. Renegociar o prazo não acelera a entrega.",
    }
