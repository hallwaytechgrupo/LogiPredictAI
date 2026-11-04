#!/usr/bin/env python3
"""Prepara os CSVs públicos da Olist para importação no LogiPredictAI.

Uso:
  python prepare_olist_csv.py --input-dir /caminho/para/olist --output pedidos_logipredict.csv

O diretório precisa conter os arquivos originais de pedidos, itens, clientes,
vendedores e produtos da Olist. O script não cria previsões; prepara as entradas
para que o Flutter envie cada pedido ao endpoint de Machine Learning.
"""
import argparse
from pathlib import Path
import pandas as pd

# Mapeia cada tabela Olist ao nome do arquivo CSV correspondente.
FILES = {
    "orders": "olist_orders_dataset.csv",
    "items": "olist_order_items_dataset.csv",
    "customers": "olist_customers_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "products": "olist_products_dataset.csv",
}


def main():
    """Ponto de entrada do script: lê os CSVs, agrega por pedido e gera o arquivo de saída."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", required=True, type=Path, help="Pasta com os CSVs originais da Olist")
    parser.add_argument("--output", default=Path("pedidos_logipredict.csv"), type=Path)
    args = parser.parse_args()

    # Constrói o caminho completo de cada arquivo esperado e valida existência.
    paths = {key: args.input_dir / filename for key, filename in FILES.items()}
    missing = [str(path) for path in paths.values() if not path.exists()]
    if missing:
        parser.error("Arquivos obrigatórios não encontrados:\n" + "\n".join(missing))

    orders = pd.read_csv(paths["orders"])
    items = pd.read_csv(paths["items"])
    customers = pd.read_csv(paths["customers"])
    sellers = pd.read_csv(paths["sellers"])
    products = pd.read_csv(paths["products"])

    # Junta itens com peso do produto e estado do vendedor.
    # Converte peso para numérico, forçando valores inválidos para NaN.
    item_data = items.merge(
        products[["product_id", "product_weight_g"]], on="product_id", how="left"
    ).merge(sellers[["seller_id", "seller_state"]], on="seller_id", how="left")
    item_data["product_weight_g"] = pd.to_numeric(item_data["product_weight_g"], errors="coerce")

    # Agrupa todos os itens de um mesmo pedido em uma única linha.
    # Soma preço, frete e peso; conta itens e vendedores únicos.
    # Estado do vendedor: usa o mais frequente (moda) quando há múltiplos vendedores.
    grouped = item_data.groupby("order_id", as_index=False).agg(
        price=("price", "sum"),
        freight_value=("freight_value", "sum"),
        total_weight_g=("product_weight_g", lambda x: x.sum(min_count=1)),
        items_count=("order_item_id", "count"),
        sellers_count=("seller_id", "nunique"),
        seller_state=("seller_state", lambda x: x.dropna().mode().iloc[0] if not x.dropna().mode().empty else None),
    )

    # Junta com dados do pedido e estado do cliente.
    data = orders.merge(grouped, on="order_id", how="inner")
    data = data.merge(customers[["customer_id", "customer_state"]], on="customer_id", how="left")

    # Renomeia colunas para o esquema interno do LogiPredictAI.
    data = data.rename(columns={
        "order_purchase_timestamp": "purchase_at",
        "order_delivered_carrier_date": "dispatched_at",
        "order_estimated_delivery_date": "estimated_delivery_at",
    })

    # Remove pedidos sem informações essenciais para a previsão.
    needed = ["order_id", "seller_state", "customer_state", "purchase_at", "dispatched_at",
              "estimated_delivery_at", "total_weight_g", "price", "freight_value"]
    data = data.dropna(subset=needed).copy()

    # Filtra valores negativos que indicam dados corrompidos.
    data = data[(data["total_weight_g"] >= 0) & (data["price"] >= 0) & (data["freight_value"] >= 0)]

    # Normaliza siglas de UF: maiúsculas e sem espaços.
    data["seller_state"] = data["seller_state"].astype(str).str.upper().str.strip()
    data["customer_state"] = data["customer_state"].astype(str).str.upper().str.strip()

    # Mantém apenas UFs brasileiras válidas.
    valid_ufs = {"AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS", "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC", "SP", "SE", "TO"}
    data = data[data.seller_state.isin(valid_ufs) & data.customer_state.isin(valid_ufs)]

    # Volume não está disponível neste script simplificado; preenche com string vazia.
    data["total_volume_cm3"] = ""

    # Seleciona e ordena as colunas de saída no formato esperado pelo Flutter.
    cols = ["order_id", "seller_state", "customer_state", "purchase_at", "dispatched_at",
            "estimated_delivery_at", "total_weight_g", "price", "freight_value",
            "items_count", "sellers_count", "total_volume_cm3"]
    data[cols].to_csv(args.output, index=False, encoding="utf-8")
    print(f"Arquivo criado: {args.output.resolve()}")
    print(f"Pedidos preparados: {len(data)}")
    print("Atenção: são registros históricos da Olist. A previsão da API é uma estimativa do modelo, não o resultado real do pedido.")

if __name__ == "__main__":
    main()
