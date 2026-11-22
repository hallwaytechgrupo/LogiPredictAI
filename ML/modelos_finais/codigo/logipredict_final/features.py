"""A mesma transformação no treino e no serviço: só usa a entrada real da main."""
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

NUMERIC = ["distance_km", "total_weight_g", "total_volume_cm3", "items_count", "sellers_count",
           "price", "freight_value", "dispatch_lead_days", "remaining_days", "purchase_month", "dispatch_weekday"]
CATEGORICAL = ["seller_state", "customer_state"]
FEATURES = NUMERIC + CATEGORICAL
REGIONS = {
    **dict.fromkeys("AC AP AM PA RO RR TO".split(), "Norte"),
    **dict.fromkeys("AL BA CE MA PB PE PI RN SE".split(), "Nordeste"),
    **dict.fromkeys("DF GO MT MS".split(), "Centro-Oeste"),
    **dict.fromkeys("ES MG RJ SP".split(), "Sudeste"),
    **dict.fromkeys("PR RS SC".split(), "Sul"),
}

def feature_frame(rows):
    """Contrato idêntico ao feature_frame da main; datas locais sem fuso."""
    out = rows.reindex(columns=FEATURES).copy()
    purchase = pd.to_datetime(rows.purchase_at)
    dispatch = pd.to_datetime(rows.dispatched_at)
    estimate = pd.to_datetime(rows.estimated_delivery_at)
    out["dispatch_lead_days"] = (dispatch-purchase).dt.total_seconds()/86400
    out["remaining_days"] = (estimate.dt.normalize()-dispatch.dt.normalize()).dt.days
    out["purchase_month"] = purchase.dt.month
    out["dispatch_weekday"] = dispatch.dt.weekday
    return out[FEATURES]

def enrich(frame, derived=True):
    """Deriva atributos das medidas, prazos e UFs, sem consultar o desfecho."""
    missing = set(FEATURES)-set(frame.columns)
    extra = set(frame.columns)-set(FEATURES)
    if missing or extra:
        raise ValueError(f"Contrato de features divergente; ausentes={sorted(missing)}, extras={sorted(extra)}")
    x = frame[FEATURES].copy()
    for column in NUMERIC:
        x[column] = pd.to_numeric(x[column], errors="raise").astype(float)
        if np.isinf(x[column]).any():
            raise ValueError(f"Valor infinito em {column}")
    for column in CATEGORICAL:
        if not x[column].isin(REGIONS).all():
            raise ValueError(f"UF inválida em {column}")
        x[column] = x[column].astype(str)
    if not derived:
        return x
    # Cruzamentos calculáveis em qualquer pedido recebido pelo serviço atual.
    x["route_state"] = x.seller_state+">"+x.customer_state
    x["seller_region"] = x.seller_state.map(REGIONS)
    x["customer_region"] = x.customer_state.map(REGIONS)
    x["interstate"] = x.seller_state.ne(x.customer_state).astype(float)
    for column in ["distance_km", "total_weight_g", "total_volume_cm3", "price", "freight_value"]:
        x["log_"+column] = np.log1p(x[column].clip(lower=0))
    x["freight_ratio"] = x.freight_value/(x.price+1)
    x["weight_per_item"] = x.total_weight_g/x.items_count
    x["price_per_item"] = x.price/x.items_count
    x["freight_per_item"] = x.freight_value/x.items_count
    x["density"] = x.total_weight_g/x.total_volume_cm3.where(x.total_volume_cm3>0)
    x["distance_per_day"] = x.distance_km/(x.remaining_days.clip(lower=0)+1)
    x["dispatch_fraction"] = x.dispatch_lead_days/(x.dispatch_lead_days+x.remaining_days.clip(lower=0)+1)
    x["promised_weekday"] = (x.dispatch_weekday+x.remaining_days)%7
    x["dispatch_weekend"] = x.dispatch_weekday.ge(5).astype(float)
    x["promised_weekend"] = x.promised_weekday.ge(5).astype(float)
    x["peak_month"] = x.purchase_month.isin([11,12]).astype(float)
    return x.replace([np.inf, -np.inf], np.nan)

def encoder(frame, scale=False):
    """Imputação e vocabulário aprendem só nas linhas de ajuste, nunca no teste."""
    categories = [c for c in frame if frame[c].dtype == object]
    numbers = [c for c in frame if c not in categories]
    numeric = SimpleImputer(strategy="median", add_indicator=True, keep_empty_features=True)
    if scale:
        numeric = make_pipeline(numeric, StandardScaler())
    return ColumnTransformer([
        ("numeric", numeric, numbers),
        ("categorical", OneHotEncoder(handle_unknown="ignore", sparse_output=True), categories),
    ], sparse_threshold=1.)
