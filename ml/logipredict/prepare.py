"""Converte seis tabelas Olist em uma linha por pedido, sem multiplicar itens."""
import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from .schema import STATES

REQUIRED = {
    "orders": ["order_id", "customer_id", "order_status", "order_purchase_timestamp",
               "order_delivered_carrier_date", "order_delivered_customer_date", "order_estimated_delivery_date"],
    "customers": ["customer_id", "customer_zip_code_prefix", "customer_state"],
    "order_items": ["order_id", "order_item_id", "product_id", "seller_id", "price", "freight_value"],
    "products": ["product_id", "product_weight_g", "product_length_cm", "product_height_cm", "product_width_cm"],
    "sellers": ["seller_id", "seller_zip_code_prefix", "seller_state"],
    "geolocation": ["geolocation_zip_code_prefix", "geolocation_lat", "geolocation_lng"],
}


def haversine(lat1, lng1, lat2, lng2):
    a1, o1, a2, o2 = map(np.radians, (lat1, lng1, lat2, lng2))
    a = np.sin((a2 - a1) / 2) ** 2 + np.cos(a1) * np.cos(a2) * np.sin((o2 - o1) / 2) ** 2
    return 6371.0088 * 2 * np.arcsin(np.sqrt(np.clip(a, 0, 1)))


def prepare(raw_dir: Path):
    tables, quality = {}, {"source": "olist", "tables": {}}
    for name, columns in REQUIRED.items():
        path = raw_dir / f"olist_{name}_dataset.csv"
        if not path.exists():
            raise ValueError(f"CSV ausente: {path}. Consulte data/README.md.")
        df = pd.read_csv(path, usecols=columns, dtype={c: "string" for c in columns if "zip_code" in c})
        before = len(df)
        df = df.drop_duplicates()
        keys = ["order_id", "order_item_id"] if name == "order_items" else [columns[0]]
        if name != "geolocation" and (df.duplicated(keys).any() or df[keys].isna().any().any()):
            raise ValueError(f"Chaves nulas ou conflitantes em {name}: {keys}")
        tables[name] = df
        quality["tables"][name] = {"input_rows": before, "exact_duplicates_removed": before - len(df)}

    geo = tables["geolocation"].copy()
    for col, bound in [("geolocation_lat", 90), ("geolocation_lng", 180)]:
        geo[col] = pd.to_numeric(geo[col], errors="coerce")
        geo.loc[~geo[col].between(-bound, bound), col] = np.nan
    geo = geo.groupby("geolocation_zip_code_prefix")[["geolocation_lat", "geolocation_lng"]].median()
    customer = tables["customers"].merge(geo, left_on="customer_zip_code_prefix", right_index=True,
                                         how="left", validate="many_to_one").rename(
        columns={"geolocation_lat": "customer_lat", "geolocation_lng": "customer_lng"})
    seller = tables["sellers"].merge(geo, left_on="seller_zip_code_prefix", right_index=True,
                                     how="left", validate="many_to_one").rename(
        columns={"geolocation_lat": "seller_lat", "geolocation_lng": "seller_lng"})
    products = tables["products"].copy()
    for col in REQUIRED["products"][1:]:
        products[col] = pd.to_numeric(products[col], errors="coerce")
        products.loc[(products[col] <= 0) | ~np.isfinite(products[col]), col] = np.nan
    products["volume"] = products.product_length_cm * products.product_height_cm * products.product_width_cm
    items = tables["order_items"].merge(products, on="product_id", how="left", validate="many_to_one")
    items = items.merge(seller, on="seller_id", how="left", validate="many_to_one")
    items = items.merge(tables["orders"][["order_id", "customer_id"]], on="order_id", validate="many_to_one")
    items = items.merge(customer, on="customer_id", how="left", validate="many_to_one")
    items["distance"] = haversine(items.seller_lat, items.seller_lng, items.customer_lat, items.customer_lng)
    for col in ["price", "freight_value"]:
        items[col] = pd.to_numeric(items[col], errors="coerce")
        items.loc[(items[col] < 0) | ~np.isfinite(items[col]), col] = np.nan

    def complete_sum(values):
        return values.sum(min_count=len(values))

    def complete_max(values):
        return values.max() if values.notna().all() else np.nan

    # Origem principal: vendedor do primeiro item. Distância: maior trajeto de todos os itens.
    items = items.sort_values(["order_id", "order_item_id"])
    grouped = items.groupby("order_id").agg(
        distance_km=("distance", complete_max), total_weight_g=("product_weight_g", complete_sum),
        total_volume_cm3=("volume", complete_sum), items_count=("order_item_id", "size"),
        sellers_count=("seller_id", "nunique"), price=("price", complete_sum),
        freight_value=("freight_value", complete_sum), seller_state=("seller_state", lambda x: x.iloc[0]),
    ).reset_index()
    orders = tables["orders"].merge(customer[["customer_id", "customer_state"]], on="customer_id",
                                    how="left", validate="many_to_one")
    orders = orders.merge(grouped, on="order_id", how="left", validate="one_to_one")
    orders = orders.rename(columns={"order_purchase_timestamp": "purchase_at",
                                    "order_delivered_carrier_date": "dispatched_at",
                                    "order_delivered_customer_date": "delivered_at",
                                    "order_estimated_delivery_date": "estimated_delivery_at"})
    for col in ["purchase_at", "dispatched_at", "delivered_at", "estimated_delivery_at"]:
        orders[col] = pd.to_datetime(orders[col], errors="coerce")
    valid = (orders.order_status.eq("delivered") & orders.purchase_at.notna() & orders.dispatched_at.notna()
             & orders.delivered_at.notna() & orders.estimated_delivery_at.notna()
             & (orders.dispatched_at >= orders.purchase_at) & (orders.delivered_at >= orders.dispatched_at)
             & (orders.estimated_delivery_at.dt.normalize() >= orders.purchase_at.dt.normalize())
             & orders.items_count.notna() & orders.price.notna() & orders.freight_value.notna()
             & orders.seller_state.isin(STATES) & orders.customer_state.isin(STATES))
    result = orders.loc[valid].copy()
    result["is_late"] = (result.delivered_at.dt.normalize() > result.estimated_delivery_at.dt.normalize()).astype(int)
    columns = ["order_id", "purchase_at", "dispatched_at", "delivered_at", "estimated_delivery_at",
               "seller_state", "customer_state", "distance_km", "total_weight_g", "total_volume_cm3",
               "items_count", "sellers_count", "price", "freight_value", "is_late"]
    result = result[columns].sort_values(["dispatched_at", "order_id"])
    quality.update(input_orders=len(orders), retained_orders=len(result), excluded_orders=int((~valid).sum()),
                   late_rate=float(result.is_late.mean()) if len(result) else None,
                   missing_features=result[["distance_km", "total_weight_g", "total_volume_cm3"]].isna().sum().to_dict())
    return result, quality


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, default=Path("data/raw"))
    parser.add_argument("--output", type=Path, default=Path("data/processed/orders.csv"))
    args = parser.parse_args()
    df, quality = prepare(args.raw_dir)
    if df.empty:
        parser.error("Nenhum pedido elegível após a limpeza.")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.output, index=False)
    args.output.with_suffix(".quality.json").write_text(json.dumps(quality, indent=2), encoding="utf-8")
    print(json.dumps(quality, indent=2))


if __name__ == "__main__":
    main()
