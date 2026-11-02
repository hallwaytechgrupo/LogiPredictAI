"""Esquema de validação e transformação de features para o modelo LogiPredictAI.

Define o modelo Pydantic `Shipment` usado para validar toda entrada de dados
antes de enviar ao modelo de machine learning. Garante que:
- UFs sejam brasileiras e em maiúsculas.
- Datas estejam em ordem cronológica (compra <= despacho <= entrega estimada).
- Valores numéricos sejam não negativos e finitos.
- Não haja vazamento de dados futuros (delivered_at, is_late) na entrada.

Também expõe a função `feature_frame()` que calcula as features temporais
compartilhadas entre treino e inferência, garantindo consistência.
"""
from datetime import datetime
from typing import Annotated

import pandas as pd
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# Conjunto de UFs brasileiras válidas para validação de estado do vendedor e cliente.
STATES = set("AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO".split())

# Lista de features numéricas usadas pelo modelo, incluindo as derivadas temporalmente.
NUMERIC = [
    "distance_km", "total_weight_g", "total_volume_cm3", "items_count", "sellers_count",
    "price", "freight_value", "dispatch_lead_days", "remaining_days", "purchase_month", "dispatch_weekday",
]

# Features categóricas: estado do vendedor e estado do cliente (one-hot encoded no pipeline).
CATEGORICAL = ["seller_state", "customer_state"]

# Ordem canônica de todas as features usadas pelo modelo.
FEATURES = NUMERIC + CATEGORICAL

# Tipo auxiliar: float não negativo, estrito (sem bool), finito (sem inf/nan).
NonNegative = Annotated[float, Field(strict=True, ge=0, allow_inf_nan=False)]


class Shipment(BaseModel):
    """Modelo de validação para um pedido de envio.

    Representa os dados mínimos necessários para prever o risco de atraso.
    Rejeita campos extras (extra="forbid") para evitar vazamento acidental
    de informações como delivered_at ou is_late.

    Atributos:
        purchase_at: Data e hora da compra.
        dispatched_at: Data e hora em que o pedido foi despachado.
        estimated_delivery_at: Data e hora estimada de entrega.
        seller_state: UF do vendedor principal (2 letras, maiúsculas).
        customer_state: UF do cliente (2 letras, maiúsculas).
        distance_km: Distância em km entre vendedor e cliente (opcional).
        total_weight_g: Peso total do pedido em gramas (opcional).
        total_volume_cm3: Volume total do pedido em cm³ (opcional).
        items_count: Quantidade de itens no pedido.
        sellers_count: Quantidade de vendedores distintos.
        price: Preço total dos produtos.
        freight_value: Valor do frete.
    """
    model_config = ConfigDict(extra="forbid")
    purchase_at: datetime
    dispatched_at: datetime
    estimated_delivery_at: datetime
    seller_state: str
    customer_state: str
    # Distância limitada ao diâmetro máximo do Brasil (~20.050 km).
    distance_km: Annotated[float, Field(strict=True, ge=0, le=20050, allow_inf_nan=False)] | None = None
    total_weight_g: NonNegative | None = None
    total_volume_cm3: NonNegative | None = None
    items_count: Annotated[int, Field(strict=True, ge=1, le=10000)]
    sellers_count: Annotated[int, Field(strict=True, ge=1, le=10000)]
    price: NonNegative
    freight_value: NonNegative

    @field_validator("seller_state", "customer_state")
    @classmethod
    def valid_state(cls, value):
        """Valida que o estado seja uma UF brasileira válida."""
        if value not in STATES:
            raise ValueError("Use uma UF brasileira em maiúsculas.")
        return value

    @model_validator(mode="after")
    def valid_dates(self):
        """Valida consistência temporal e lógica entre os campos do pedido.

        Verifica:
        - Datas sem fuso horário (datas locais, como na base Olist).
        - Despacho não antecede a compra.
        - Entrega estimada não antecede a compra.
        - Número de vendedores não excede o de itens.
        """
        dates = (self.purchase_at, self.dispatched_at, self.estimated_delivery_at)
        if any(d.tzinfo is not None for d in dates):
            raise ValueError("Use datas locais sem fuso, como na base Olist.")
        if self.dispatched_at < self.purchase_at:
            raise ValueError("Despacho não pode anteceder a compra.")
        if self.estimated_delivery_at.date() < self.purchase_at.date():
            raise ValueError("Previsão de entrega não pode anteceder a compra.")
        if self.sellers_count > self.items_count:
            raise ValueError("Quantidade de vendedores excede a de itens.")
        return self


def feature_frame(rows: pd.DataFrame) -> pd.DataFrame:
    """Calcula as features temporais a partir das datas do pedido.

    Esta é a única transformação aplicada tanto no treino quanto na inferência,
    garantindo que o modelo receba exatamente as mesmas features em ambos os contextos.

    Features derivadas:
        dispatch_lead_days: Dias entre compra e despacho (lead time do vendedor).
        remaining_days: Dias restantes entre despacho e entrega estimada.
        purchase_month: Mês da compra (1-12), captura sazonalidade.
        dispatch_weekday: Dia da semana do despacho (0=segunda, 6=domingo).

    Args:
        rows: DataFrame com colunas purchase_at, dispatched_at, estimated_delivery_at
              e as features originais (seller_state, customer_state, etc.).

    Returns:
        DataFrame com apenas as colunas de FEATURES na ordem canônica.
    """
    result = rows.reindex(columns=FEATURES).copy()
    purchase = pd.to_datetime(rows["purchase_at"])
    dispatch = pd.to_datetime(rows["dispatched_at"])
    estimate = pd.to_datetime(rows["estimated_delivery_at"])
    result["dispatch_lead_days"] = (dispatch - purchase).dt.total_seconds() / 86400
    result["remaining_days"] = (estimate.dt.normalize() - dispatch.dt.normalize()).dt.days
    result["purchase_month"] = purchase.dt.month
    result["dispatch_weekday"] = dispatch.dt.weekday
    return result[FEATURES]