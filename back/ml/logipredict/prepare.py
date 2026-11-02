"""Converte seis tabelas Olist em uma linha por pedido, sem multiplicar itens.

Este módulo realiza o ETL completo dos dados brutos da Olist:
1. Lê 6 CSVs (pedidos, clientes, itens, produtos, vendedores, geolocalização).
2. Valida integridade das chaves primárias.
3. Calcula distância geográfica Haversine entre vendedor e cliente.
4. Agrega múltiplos itens em uma linha por pedido.
5. Filtra apenas pedidos entregues com dados consistentes.
6. Calcula o rótulo is_late (atraso) comparando data de entrega com o prazo prometido.

O resultado é um DataFrame pronto para treino do modelo de machine learning.
"""
import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from .schema import STATES

# Esquema esperado: para cada tabela Olist, lista as colunas obrigatórias.
# Usado para validação e leitura seletiva (usecols), reduzindo consumo de memória.
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
    """Calcula a distância em km entre dois pontos geográficos usando a fórmula de Haversine.

    Usa o raio médio da Terra (6371.0088 km) e opera com arrays NumPy para
    calcular distâncias vetorizadas entre todos os vendedores e clientes.

    Args:
        lat1: Latitude de origem (vendedor) em graus.
        lng1: Longitude de origem (vendedor) em graus.
        lat2: Latitude de destino (cliente) em graus.
        lng2: Longitude de destino (cliente) em graus.

    Returns:
        Distância em quilômetros entre os dois pontos.
    """
    a1, o1, a2, o2 = map(np.radians, (lat1, lng1, lat2, lng2))
    a = np.sin((a2 - a1) / 2) ** 2 + np.cos(a1) * np.cos(a2) * np.sin((o2 - o1) / 2) ** 2
    return 6371.0088 * 2 * np.arcsin(np.sqrt(np.clip(a, 0, 1)))


def prepare(raw_dir: Path):
    """Executa o pipeline ETL completo a partir dos CSVs brutos da Olist.

    Lê, valida, enriquece e filtra os dados para produzir um DataFrame
    com uma linha por pedido entregue, pronto para treino do modelo.

    Args:
        raw_dir: Caminho para o diretório com os 6 CSVs da Olist.

    Returns:
        Uma tupla (DataFrame, dict) onde:
        - DataFrame contém uma linha por pedido com features e rótulo is_late.
        - dict contém métricas de qualidade: linhas lidas, removidas, taxa de atraso, etc.

    Raises:
        ValueError: Se algum CSV obrigatório estiver ausente ou com chaves duplicadas/nulas.
    """
    # Fase 1: Leitura e validação de cada tabela.
    tables, quality = {}, {"source": "olist", "tables": {}}
    for name, columns in REQUIRED.items():
        path = raw_dir / f"olist_{name}_dataset.csv"
        if not path.exists():
            raise ValueError(f"CSV ausente: {path}. Consulte data/README.md.")
        # Lê apenas as colunas necessárias; CEP como string para preservar zeros à esquerda.
        df = pd.read_csv(path, usecols=columns, dtype={c: "string" for c in columns if "zip_code" in c})
        before = len(df)
        df = df.drop_duplicates()
        # Valida integridade das chaves primárias.
        keys = ["order_id", "order_item_id"] if name == "order_items" else [columns[0]]
        if name != "geolocation" and (df.duplicated(keys).any() or df[keys].isna().any().any()):
            raise ValueError(f"Chaves nulas ou conflitantes em {name}: {keys}")
        tables[name] = df
        quality["tables"][name] = {"input_rows": before, "exact_duplicates_removed": before - len(df)}

    # Fase 2: Geolocalização — converte para numérico, valida limites e agrega por CEP.
    # Usa mediana quando há múltiplas coordenadas para o mesmo CEP.
    geo = tables["geolocation"].copy()
    for col, bound in [("geolocation_lat", 90), ("geolocation_lng", 180)]:
        geo[col] = pd.to_numeric(geo[col], errors="coerce")
        geo.loc[~geo[col].between(-bound, bound), col] = np.nan
    geo = geo.groupby("geolocation_zip_code_prefix")[["geolocation_lat", "geolocation_lng"]].median()

    # Junta geolocalização com clientes e vendedores pelo CEP.
    customer = tables["customers"].merge(geo, left_on="customer_zip_code_prefix", right_index=True,
                                         how="left", validate="many_to_one").rename(
        columns={"geolocation_lat": "customer_lat", "geolocation_lng": "customer_lng"})
    seller = tables["sellers"].merge(geo, left_on="seller_zip_code_prefix", right_index=True,
                                     how="left", validate="many_to_one").rename(
        columns={"geolocation_lat": "seller_lat", "geolocation_lng": "seller_lng"})

    # Fase 3: Produtos — converte dimensões para numérico e calcula volume.
    # Valores não positivos ou infinitos são tratados como ausentes (NaN).
    products = tables["products"].copy()
    for col in REQUIRED["products"][1:]:
        products[col] = pd.to_numeric(products[col], errors="coerce")
        products.loc[(products[col] <= 0) | ~np.isfinite(products[col]), col] = np.nan
    products["volume"] = products.product_length_cm * products.product_height_cm * products.product_width_cm

    # Fase 4: Constrói tabela de itens enriquecida com produto, vendedor, cliente e distância.
    items = tables["order_items"].merge(products, on="product_id", how="left", validate="many_to_one")
    items = items.merge(seller, on="seller_id", how="left", validate="many_to_one")
    items = items.merge(tables["orders"][["order_id", "customer_id"]], on="order_id", validate="many_to_one")
    items = items.merge(customer, on="customer_id", how="left", validate="many_to_one")
    items["distance"] = haversine(items.seller_lat, items.seller_lng, items.customer_lat, items.customer_lng)
    for col in ["price", "freight_value"]:
        items[col] = pd.to_numeric(items[col], errors="coerce")
        items.loc[(items[col] < 0) | ~np.isfinite(items[col]), col] = np.nan

    # Funções de agregação que retornam NaN se qualquer valor estiver ausente.
    # Garante que pedidos com dados incompletos sejam detectáveis.
    def complete_sum(values):
        """Soma apenas se todos os valores estiverem presentes; senão retorna NaN."""
        return values.sum(min_count=len(values))

    def complete_max(values):
        """Máximo apenas se todos os valores estiverem presentes; senão retorna NaN."""
        return values.max() if values.notna().all() else np.nan

    # Ordena itens para garantir que o primeiro item (menor order_item_id)
    # determine o estado do vendedor principal.
    items = items.sort_values(["order_id", "order_item_id"])
    grouped = items.groupby("order_id").agg(
        # Distância do pedido: maior trajeto entre todos os itens (pior caso).
        distance_km=("distance", complete_max),
        total_weight_g=("product_weight_g", complete_sum),
        total_volume_cm3=("volume", complete_sum),
        items_count=("order_item_id", "size"),
        sellers_count=("seller_id", "nunique"),
        price=("price", complete_sum),
        freight_value=("freight_value", complete_sum),
        # Estado do vendedor: usa o primeiro item como referência.
        seller_state=("seller_state", lambda x: x.iloc[0]),
    ).reset_index()

    # Fase 5: Junta com dados do pedido e estado do cliente.
    orders = tables["orders"].merge(customer[["customer_id", "customer_state"]], on="customer_id",
                                    how="left", validate="many_to_one")
    orders = orders.merge(grouped, on="order_id", how="left", validate="one_to_one")

    # Renomeia colunas para o esquema interno do LogiPredictAI.
    orders = orders.rename(columns={"order_purchase_timestamp": "purchase_at",
                                    "order_delivered_carrier_date": "dispatched_at",
                                    "order_delivered_customer_date": "delivered_at",
                                    "order_estimated_delivery_date": "estimated_delivery_at"})

    # Converte colunas de data para datetime, forçando valores inválidos para NaT.
    for col in ["purchase_at", "dispatched_at", "delivered_at", "estimated_delivery_at"]:
        orders[col] = pd.to_datetime(orders[col], errors="coerce")

    # Fase 6: Filtra apenas pedidos entregues com dados temporais e numéricos consistentes.
    # Condições:
    # - Status "delivered" (entregue).
    # - Todas as 4 datas presentes.
    # - Ordem temporal: compra <= despacho <= entrega.
    # - Prazo estimado >= data da compra.
    # - Features numéricas não nulas.
    # - UFs válidas (vendedor e cliente).
    valid = (orders.order_status.eq("delivered") & orders.purchase_at.notna() & orders.dispatched_at.notna()
             & orders.delivered_at.notna() & orders.estimated_delivery_at.notna()
             & (orders.dispatched_at >= orders.purchase_at) & (orders.delivered_at >= orders.dispatched_at)
             & (orders.estimated_delivery_at.dt.normalize() >= orders.purchase_at.dt.normalize())
             & orders.items_count.notna() & orders.price.notna() & orders.freight_value.notna()
             & orders.seller_state.isin(STATES) & orders.customer_state.isin(STATES))
    result = orders.loc[valid].copy()

    # Calcula rótulo de atraso: compara data calendário de entrega com data calendário prometida.
    # Usa normalize() para ignorar horas — entregar à noite no dia prometido não é atraso.
    result["is_late"] = (result.delivered_at.dt.normalize() > result.estimated_delivery_at.dt.normalize()).astype(int)

    # Seleciona colunas finais e ordena por data de despacho.
    columns = ["order_id", "purchase_at", "dispatched_at", "delivered_at", "estimated_delivery_at",
               "seller_state", "customer_state", "distance_km", "total_weight_g", "total_volume_cm3",
               "items_count", "sellers_count", "price", "freight_value", "is_late"]
    result = result[columns].sort_values(["dispatched_at", "order_id"])

    # Registra métricas de qualidade do pipeline.
    quality.update(input_orders=len(orders), retained_orders=len(result), excluded_orders=int((~valid).sum()),
                   late_rate=float(result.is_late.mean()) if len(result) else None,
                   missing_features=result[["distance_km", "total_weight_g", "total_volume_cm3"]].isna().sum().to_dict())
    return result, quality


def main():
    """Ponto de entrada do script: executa o ETL e salva o CSV processado e o relatório de qualidade."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, default=Path("data/raw"))
    parser.add_argument("--output", type=Path, default=Path("data/processed/orders.csv"))
    args = parser.parse_args()
    df, quality = prepare(args.raw_dir)
    if df.empty:
        parser.error("Nenhum pedido elegível após a limpeza.")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.output, index=False)
    # Salva relatório de qualidade ao lado do CSV, com o mesmo nome e extensão .quality.json.
    args.output.with_suffix(".quality.json").write_text(json.dumps(quality, indent=2), encoding="utf-8")
    print(json.dumps(quality, indent=2))


if __name__ == "__main__":
    main()