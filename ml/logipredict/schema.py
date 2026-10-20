from datetime import datetime
from typing import Annotated

import pandas as pd
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

STATES = set("AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO".split())
NUMERIC = [
    "distance_km", "total_weight_g", "total_volume_cm3", "items_count", "sellers_count",
    "price", "freight_value", "dispatch_lead_days", "remaining_days", "purchase_month", "dispatch_weekday",
]
CATEGORICAL = ["seller_state", "customer_state"]
FEATURES = NUMERIC + CATEGORICAL
NonNegative = Annotated[float, Field(strict=True, ge=0, allow_inf_nan=False)]


class Shipment(BaseModel):
    model_config = ConfigDict(extra="forbid")
    purchase_at: datetime
    dispatched_at: datetime
    estimated_delivery_at: datetime
    seller_state: str
    customer_state: str
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
        if value not in STATES:
            raise ValueError("Use uma UF brasileira em maiúsculas.")
        return value

    @model_validator(mode="after")
    def valid_dates(self):
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
    """Única transformação temporal usada tanto no treino quanto na inferência."""
    result = rows.reindex(columns=FEATURES).copy()
    purchase = pd.to_datetime(rows["purchase_at"])
    dispatch = pd.to_datetime(rows["dispatched_at"])
    estimate = pd.to_datetime(rows["estimated_delivery_at"])
    result["dispatch_lead_days"] = (dispatch - purchase).dt.total_seconds() / 86400
    result["remaining_days"] = (estimate.dt.normalize() - dispatch.dt.normalize()).dt.days
    result["purchase_month"] = purchase.dt.month
    result["dispatch_weekday"] = dispatch.dt.weekday
    return result[FEATURES]
