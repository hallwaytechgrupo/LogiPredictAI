#!/usr/bin/env python3
"""Script interativo para remover pedidos de demonstração Olist do banco de dados local.

Identifica pedidos cujo order_id começa com "DEMO-OLIST-" e os remove de
orders.json e predictions.json, criando backup antes de qualquer alteração.

Uso:
    python limpar_olist_demo.py

O script exige confirmação explícita do usuário antes de modificar arquivos.
"""
import json
import shutil
from datetime import datetime
from pathlib import Path

# Diretório base onde os arquivos JSON de pedidos e previsões são armazenados.
BASE = Path("/home/mario/LogiPredictAI/back/data/hubs")

ORDERS_FILE = BASE / "orders.json"
PREDICTIONS_FILE = BASE / "predictions.json"

# Prefixo que identifica pedidos importados da demonstração Olist.
PREFIX = "DEMO-OLIST-"


def load_json(path):
    """Carrega um arquivo JSON e retorna o objeto parseado."""
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_json_atomic(path, data):
    """Grava em arquivo temporário e substitui o original.

    Garante que o arquivo original não fique corrompido se a gravação falhar.
    """
    temp = path.with_suffix(path.suffix + ".tmp")
    with temp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    temp.replace(path)


def main():
    """Executa o fluxo interativo de limpeza dos pedidos DEMO-OLIST."""
    if not ORDERS_FILE.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {ORDERS_FILE}")

    if not PREDICTIONS_FILE.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {PREDICTIONS_FILE}")

    orders = load_json(ORDERS_FILE)
    predictions = load_json(PREDICTIONS_FILE)

    if not isinstance(orders, list):
        raise TypeError("orders.json não contém uma lista.")

    if not isinstance(predictions, list):
        raise TypeError("predictions.json não contém uma lista.")

    # Identifica apenas pedidos de demonstração Olist pelo prefixo do ID.
    demo_order_ids = {
        str(order.get("order_id"))
        for order in orders
        if str(order.get("order_id", "")).startswith(PREFIX)
    }

    orders_to_remove = [
        order for order in orders
        if str(order.get("order_id", "")).startswith(PREFIX)
    ]

    predictions_to_remove = [
        prediction for prediction in predictions
        if str(prediction.get("order_id", "")) in demo_order_ids
    ]

    remaining_orders = [
        order for order in orders
        if not str(order.get("order_id", "")).startswith(PREFIX)
    ]

    remaining_predictions = [
        prediction for prediction in predictions
        if str(prediction.get("order_id", "")) not in demo_order_ids
    ]

    # Exibe resumo antes de solicitar confirmação.
    print("\nPrévia da limpeza")
    print("-----------------")
    print(f"Pedidos atuais: {len(orders)}")
    print(f"Pedidos DEMO-OLIST a remover: {len(orders_to_remove)}")
    print(f"Pedidos restantes: {len(remaining_orders)}")
    print(f"Previsões atuais: {len(predictions)}")
    print(f"Previsões associadas a esses pedidos: {len(predictions_to_remove)}")
    print(f"Previsões restantes: {len(remaining_predictions)}")
    print("predictions.jsonl: será preservado")
    print("hubs.json: será preservado")

    if not demo_order_ids:
        print("\nNenhum pedido DEMO-OLIST encontrado. Nada foi alterado.")
        return

    # Exige confirmação explícita para evitar exclusão acidental.
    confirm = input(
        "\nDigite APAGAR OLIST DEMO para confirmar a limpeza: "
    )

    if confirm != "APAGAR OLIST DEMO":
        print("Cancelado. Nenhum arquivo foi alterado.")
        return

    # Cria backup com timestamp antes de alterar qualquer arquivo.
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = BASE / f"backup_limpeza_olist_{timestamp}"
    backup_dir.mkdir(parents=True, exist_ok=False)

    shutil.copy2(ORDERS_FILE, backup_dir / "orders.json")
    shutil.copy2(PREDICTIONS_FILE, backup_dir / "predictions.json")

    # Atualiza os dois arquivos somente após backup bem-sucedido.
    save_json_atomic(ORDERS_FILE, remaining_orders)
    save_json_atomic(PREDICTIONS_FILE, remaining_predictions)

    print("\nLimpeza concluída.")
    print(f"Backup salvo em: {backup_dir}")
    print(f"Pedidos removidos: {len(orders_to_remove)}")
    print(f"Previsões removidas: {len(predictions_to_remove)}")
    print(f"Pedidos restantes: {len(remaining_orders)}")
    print(f"Previsões restantes: {len(remaining_predictions)}")


if __name__ == "__main__":
    main()
