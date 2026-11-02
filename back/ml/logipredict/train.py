"""Treino temporal com rótulos disponíveis antes de cada corte e teste reservado.

Este módulo implementa o pipeline completo de treinamento do modelo de previsão
de atraso em entregas logísticas. O algoritmo principal é Random Forest (sklearn),
com divisão temporal estrita para evitar vazamento de dados futuros.

Fluxo:
1. Valida integridade dos rótulos is_late.
2. Divide os dados em treino (60%), validação (20%) e teste (20%) por data de despacho.
3. Purga rótulos ainda indisponíveis nos cortes (delivered_at futuro).
4. Treina o pipeline (imputação + one-hot + Random Forest).
5. Seleciona o limiar de decisão na validação, maximizando F1.
6. Avalia no conjunto de teste e compara com baseline majoritária.
7. Gera artefatos: modelo serializado, métricas JSON, gráficos e relatório Markdown.
"""
import argparse
import hashlib
import json
import platform
from datetime import datetime, timezone
from pathlib import Path

import joblib
import matplotlib
import numpy as np
import pandas as pd
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import (
    ConfusionMatrixDisplay, PrecisionRecallDisplay, accuracy_score, average_precision_score,
    brier_score_loss, confusion_matrix, f1_score, precision_score, recall_score, roc_auc_score,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

from .schema import CATEGORICAL, FEATURES, NUMERIC, feature_frame

# Usa backend não interativo para gerar gráficos sem display.
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def temporal_split(frame):
    """Divide os dados em treino, validação e teste usando cortes temporais estritos.

    Evita vazamento de dados futuros: um pedido só entra no treino se o resultado
    (entrega) já for conhecido antes do início do período seguinte.

    Divisão por data de despacho:
    - Treino: 60% mais antigos, com delivered_at antes do corte de validação.
    - Validação: 20% intermediários, com delivered_at antes do corte de teste.
    - Teste: 20% mais recentes (sem restrição de delivered_at).

    Args:
        frame: DataFrame ordenado com colunas order_id, dispatched_at, delivered_at, is_late.

    Returns:
        Tupla (train, validation, test) com os DataFrames de cada período.

    Raises:
        ValueError: Se order_id tiver duplicatas, se houver <100 pedidos,
                    ou se algum período tiver <20 pedidos ou apenas uma classe.
    """
    if frame.order_id.isna().any() or frame.order_id.duplicated().any():
        raise ValueError("Cada order_id deve ser único e não nulo.")
    ordered = frame.sort_values(["dispatched_at", "order_id"]).reset_index(drop=True)
    if len(ordered) < 100:
        raise ValueError("São necessários ao menos 100 pedidos elegíveis.")

    # Cortes temporais baseados em percentis de dispatched_at.
    validation_start = ordered.dispatched_at.iloc[int(len(ordered) * 0.6)]
    test_start = ordered.dispatched_at.iloc[int(len(ordered) * 0.8)]

    # Purge: remove do treino e validação os pedidos cujo resultado ainda não
    # seria conhecido no início do período seguinte — evita data leakage.
    train = ordered[(ordered.dispatched_at < validation_start) & (ordered.delivered_at < validation_start)]
    validation = ordered[(ordered.dispatched_at >= validation_start) & (ordered.dispatched_at < test_start)
                         & (ordered.delivered_at < test_start)]
    test = ordered[ordered.dispatched_at >= test_start]

    # Valida que cada período tem amostra suficiente e ambas as classes representadas.
    for name, part in [("train", train), ("validation", validation), ("test", test)]:
        if len(part) < 20 or set(part.is_late.unique()) != {0, 1}:
            raise ValueError(f"Período {name} precisa de >=20 pedidos e das duas classes. Amplie a base.")
    return train, validation, test


def build_pipeline(trees=250):
    """Constrói o pipeline de pré-processamento + classificação.

    Pré-processamento:
    - Numéricas: imputação por mediana com indicador de valor ausente.
    - Categóricas: One-Hot Encoding, ignorando categorias desconhecidas.

    Classificador: Random Forest com balanceamento de classes por subsample,
    profundidade limitada (16) e folha mínima (5) para reduzir overfitting.

    Args:
        trees: Número de árvores na floresta aleatória.

    Returns:
        Pipeline sklearn pronto para treino.
    """
    preprocess = ColumnTransformer([
        ("numeric", SimpleImputer(strategy="median", add_indicator=True, keep_empty_features=True), NUMERIC),
        ("categorical", OneHotEncoder(handle_unknown="ignore", sparse_output=False), CATEGORICAL),
    ])
    return Pipeline([
        ("preprocess", preprocess),
        ("classifier", RandomForestClassifier(n_estimators=trees, max_depth=16, min_samples_leaf=5,
                                               class_weight="balanced_subsample", n_jobs=-1, random_state=42)),
    ])


def scores(y, probability, threshold):
    """Calcula métricas de classificação a partir de probabilidades e um limiar.

    Args:
        y: Rótulos reais (0 = no prazo, 1 = atraso).
        probability: Probabilidades previstas da classe positiva (atraso).
        threshold: Limiar para converter probabilidade em classe discreta.

    Returns:
        Dicionário com accuracy, precision, recall, f1, average_precision,
        roc_auc, brier_score e confusion_matrix.
    """
    prediction = probability >= threshold
    return {
        "accuracy": float(accuracy_score(y, prediction)),
        "precision": float(precision_score(y, prediction, zero_division=0)),
        "recall": float(recall_score(y, prediction, zero_division=0)),
        "f1": float(f1_score(y, prediction, zero_division=0)),
        "average_precision": float(average_precision_score(y, probability)),
        "roc_auc": float(roc_auc_score(y, probability)),
        "brier_score": float(brier_score_loss(y, probability)),
        "confusion_matrix": confusion_matrix(y, prediction, labels=[0, 1]).tolist(),
    }


def train(input_path, model_dir, report_dir, source, trees=250):
    """Executa o treinamento completo do modelo e gera todos os artefatos.

    Fluxo:
    1. Lê o CSV processado e valida os rótulos.
    2. Divide temporalmente em treino, validação e teste.
    3. Treina o pipeline e seleciona o limiar na validação.
    4. Avalia no teste e compara com baseline.
    5. Salva modelo, metadados, métricas, gráficos e relatório.

    Args:
        input_path: Caminho para o CSV processado (saída do prepare.py).
        model_dir: Diretório para salvar o modelo e metadados.
        report_dir: Diretório para salvar gráficos e relatório.
        source: "olist" para dados reais ou "synthetic" para dados artificiais.
        trees: Número de árvores na Random Forest.

    Returns:
        Dicionário com metadados completos do treinamento.
    """
    frame = pd.read_csv(input_path, parse_dates=["purchase_at", "dispatched_at", "delivered_at",
                                                "estimated_delivery_at"])

    # Valida que os rótulos is_late correspondem ao cálculo esperado.
    expected = (frame.delivered_at.dt.normalize() > frame.estimated_delivery_at.dt.normalize()).astype(int)
    if not frame.is_late.equals(expected):
        raise ValueError("Rótulo inconsistente: regenere o CSV pelo pipeline oficial.")

    # Impede confundir dados sintéticos com dados reais da Olist.
    if source == "olist" and frame.order_id.astype(str).str.startswith("synthetic-").any():
        raise ValueError("Dados sintéticos não podem ser identificados como Olist.")

    # Divide os dados e calcula features.
    parts = temporal_split(frame)
    training, validation, test = parts
    x_train, x_val, x_test = map(feature_frame, parts)

    # Treina o modelo.
    model = build_pipeline(trees)
    model.fit(x_train, training.is_late)

    # Seleciona o limiar de decisão na validação, maximizando F1.
    # Não usa o conjunto de teste para evitar overfitting no limiar.
    val_probability = model.predict_proba(x_val)[:, 1]
    thresholds = np.linspace(0.05, 0.95, 91)
    threshold = float(max(thresholds, key=lambda t: f1_score(validation.is_late, val_probability >= t)))

    # Avalia no conjunto de teste.
    probability = model.predict_proba(x_test)[:, 1]

    # Baseline: classificador ingênuo que sempre prevê a classe majoritária.
    baseline = DummyClassifier(strategy="prior").fit(x_train, training.is_late)
    base_probability = baseline.predict_proba(x_test)[:, 1]

    # Gera identificador único baseado no hash do dataset.
    digest = hashlib.sha256(input_path.read_bytes()).hexdigest()
    version = f"rf-{source}-{digest[:12]}"

    # Compila metadados completos para rastreabilidade e reprodutibilidade.
    metadata = {
        "version": version, "source": source, "synthetic": source == "synthetic",
        "trained_at": datetime.now(timezone.utc).isoformat(), "dataset_sha256": digest,
        "python_version": platform.python_version(), "sklearn_version": sklearn.__version__,
        "algorithm": "RandomForestClassifier", "features": FEATURES, "seed": 42,
        "parameters": model.named_steps["classifier"].get_params(),
        "threshold": threshold, "threshold_selection": "max F1 on validation only",
        "target": "delivered_calendar_date > estimated_calendar_date",
        "prediction_time": "dispatch", "probability_calibrated": False,
        "split": {name: {"rows": len(part), "late_rate": float(part.is_late.mean()),
                          "dispatch_min": str(part.dispatched_at.min()),
                          "dispatch_max": str(part.dispatched_at.max()),
                          "outcome_max": str(part.delivered_at.max())}
                  for name, part in zip(["train", "validation", "test"], parts)},
        "purged_rows": len(frame) - sum(map(len, parts)),
        "validation": scores(validation.is_late, val_probability, threshold),
        "test": scores(test.is_late, probability, threshold),
        "baseline_test": scores(test.is_late, base_probability, 0.5),
        "baseline_description": "DummyClassifier(prior), decisão majoritária a 0.5",
    }

    # Salva artefatos do modelo.
    model_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)
    joblib.dump({"pipeline": model, "metadata": metadata}, model_dir / "model.joblib", compress=3)
    (model_dir / "metadata.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    (report_dir / "metrics.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")

    # Calcula taxa de atraso histórica por UF do cliente para análise geográfica.
    historical = frame.groupby("customer_state").agg(orders=("is_late", "size"), late_orders=("is_late", "sum"))
    historical["late_rate"] = historical.late_orders / historical.orders
    analytics = {"source": source, "synthetic": source == "synthetic", "type": "historical_observed",
                 "period_start": str(frame.dispatched_at.min()), "period_end": str(frame.dispatched_at.max()),
                 "states": historical.reset_index().to_dict(orient="records")}
    (model_dir / "analytics.json").write_text(json.dumps(analytics, indent=2), encoding="utf-8")

    # Importância dos atributos (Gini impurity decrease) — não implica causalidade.
    names = model.named_steps["preprocess"].get_feature_names_out()
    importance = pd.Series(model.named_steps["classifier"].feature_importances_, index=names)
    importance.sort_values(ascending=False).to_csv(report_dir / "feature_importance.csv", header=["importance"])

    # Gera gráficos de avaliação.
    label = "SINTÉTICO — validação técnica" if source == "synthetic" else "Olist — teste temporal"

    # Matriz de confusão.
    ConfusionMatrixDisplay.from_predictions(test.is_late, probability >= threshold,
                                            display_labels=["No prazo", "Atraso"], colorbar=False)
    plt.title(label)
    plt.tight_layout()
    plt.savefig(report_dir / "confusion_matrix.png", dpi=150)
    plt.close()

    # Curva Precision-Recall com linha de prevalência.
    PrecisionRecallDisplay.from_predictions(test.is_late, probability, name="Random Forest")
    plt.axhline(test.is_late.mean(), color="gray", linestyle="--", label="Prevalência no teste")
    plt.legend()
    plt.title(label)
    plt.tight_layout()
    plt.savefig(report_dir / "precision_recall.png", dpi=150)
    plt.close()

    # Gráfico de importância dos atributos (top 12).
    importance.nlargest(12).sort_values().plot.barh(figsize=(9, 5))
    plt.title(f"{label}\nImportância por impureza (não é causalidade)")
    plt.tight_layout()
    plt.savefig(report_dir / "feature_importance.png", dpi=150)
    plt.close()

    # Gera relatório Markdown com métricas e links para gráficos.
    report = f"""# Relatório de treinamento

Fonte: **{source}**. Modelo: `{version}`. Hash SHA-256: `{digest}`.
{"**DADOS SINTÉTICOS. Estes resultados não medem desempenho real na Olist.**" if source == "synthetic" else "Base histórica Olist; resultados não garantem desempenho em operações atuais."}

Divisão por despacho: 60% / 20% / 20%, com remoção de rótulos ainda indisponíveis nos cortes.
Treino: {len(training)}; validação: {len(validation)}; teste: {len(test)}; removidos nos cortes: {metadata['purged_rows']}.
Limiar selecionado somente na validação: {threshold:.2f}. O artefato mantém o modelo avaliado, sem retreino no teste.

| Métrica de teste | Random Forest | Baseline majoritária |
| --- | ---: | ---: |
"""
    for metric in ["accuracy", "precision", "recall", "f1", "average_precision", "roc_auc", "brier_score"]:
        report += f"| {metric} | {metadata['test'][metric]:.4f} | {metadata['baseline_test'][metric]:.4f} |\n"
    report += """
Probabilidade não calibrada; limiar acadêmico por F1 ainda requer validação do custo dos erros.
AP significa Average Precision, não a integral trapezoidal da curva PR.
Matriz: linhas = classes reais; colunas = previstas; ordem = [no prazo, atraso].

![Matriz de confusão](confusion_matrix.png)
![Curva de precisão e recall](precision_recall.png)
![Importância dos atributos](feature_importance.png)
"""
    (report_dir / "README.md").write_text(report, encoding="utf-8")

    # Imprime resumo no stdout para consumo por scripts externos.
    print(json.dumps({"model_dir": str(model_dir), "source": source, "threshold": threshold,
                      "test": metadata["test"]}, indent=2))
    return metadata


def main():
    """Ponto de entrada do script de treinamento.

    Uso:
        python -m logipredict.train --source olist
        python -m logipredict.train --source synthetic --trees 100
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("data/processed/orders.csv"))
    parser.add_argument("--model-dir", type=Path, default=Path("models/olist"))
    parser.add_argument("--report-dir", type=Path, default=Path("reports/local/olist"))
    parser.add_argument("--source", choices=["olist", "synthetic"], required=True)
    parser.add_argument("--trees", type=int, default=250)
    args = parser.parse_args()
    if args.trees < 1:
        parser.error("--trees precisa ser positivo.")
    train(args.input, args.model_dir, args.report_dir, args.source, args.trees)


if __name__ == "__main__":
    main()