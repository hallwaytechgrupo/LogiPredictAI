"""Treino temporal com rótulos disponíveis antes de cada corte e teste reservado."""
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

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def temporal_split(frame):
    if frame.order_id.isna().any() or frame.order_id.duplicated().any():
        raise ValueError("Cada order_id deve ser único e não nulo.")
    ordered = frame.sort_values(["dispatched_at", "order_id"]).reset_index(drop=True)
    if len(ordered) < 100:
        raise ValueError("São necessários ao menos 100 pedidos elegíveis.")
    validation_start = ordered.dispatched_at.iloc[int(len(ordered) * 0.6)]
    test_start = ordered.dispatched_at.iloc[int(len(ordered) * 0.8)]
    # Um pedido anterior ao corte só pode ensinar o modelo após o resultado ser conhecido.
    train = ordered[(ordered.dispatched_at < validation_start) & (ordered.delivered_at < validation_start)]
    validation = ordered[(ordered.dispatched_at >= validation_start) & (ordered.dispatched_at < test_start)
                         & (ordered.delivered_at < test_start)]
    test = ordered[ordered.dispatched_at >= test_start]
    for name, part in [("train", train), ("validation", validation), ("test", test)]:
        if len(part) < 20 or set(part.is_late.unique()) != {0, 1}:
            raise ValueError(f"Período {name} precisa de >=20 pedidos e das duas classes. Amplie a base.")
    return train, validation, test


def build_pipeline(trees=250):
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
    frame = pd.read_csv(input_path, parse_dates=["purchase_at", "dispatched_at", "delivered_at",
                                                "estimated_delivery_at"])
    expected = (frame.delivered_at.dt.normalize() > frame.estimated_delivery_at.dt.normalize()).astype(int)
    if not frame.is_late.equals(expected):
        raise ValueError("Rótulo inconsistente: regenere o CSV pelo pipeline oficial.")
    if source == "olist" and frame.order_id.astype(str).str.startswith("synthetic-").any():
        raise ValueError("Dados sintéticos não podem ser identificados como Olist.")
    parts = temporal_split(frame)
    training, validation, test = parts
    x_train, x_val, x_test = map(feature_frame, parts)
    model = build_pipeline(trees)
    model.fit(x_train, training.is_late)
    val_probability = model.predict_proba(x_val)[:, 1]
    thresholds = np.linspace(0.05, 0.95, 91)
    threshold = float(max(thresholds, key=lambda t: f1_score(validation.is_late, val_probability >= t)))
    probability = model.predict_proba(x_test)[:, 1]
    baseline = DummyClassifier(strategy="prior").fit(x_train, training.is_late)
    base_probability = baseline.predict_proba(x_test)[:, 1]
    digest = hashlib.sha256(input_path.read_bytes()).hexdigest()
    version = f"rf-{source}-{digest[:12]}"
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
    model_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)
    joblib.dump({"pipeline": model, "metadata": metadata}, model_dir / "model.joblib", compress=3)
    (model_dir / "metadata.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    (report_dir / "metrics.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    historical = frame.groupby("customer_state").agg(orders=("is_late", "size"), late_orders=("is_late", "sum"))
    historical["late_rate"] = historical.late_orders / historical.orders
    analytics = {"source": source, "synthetic": source == "synthetic", "type": "historical_observed",
                 "period_start": str(frame.dispatched_at.min()), "period_end": str(frame.dispatched_at.max()),
                 "states": historical.reset_index().to_dict(orient="records")}
    (model_dir / "analytics.json").write_text(json.dumps(analytics, indent=2), encoding="utf-8")
    names = model.named_steps["preprocess"].get_feature_names_out()
    importance = pd.Series(model.named_steps["classifier"].feature_importances_, index=names)
    importance.sort_values(ascending=False).to_csv(report_dir / "feature_importance.csv", header=["importance"])
    label = "SINTÉTICO — validação técnica" if source == "synthetic" else "Olist — teste temporal"
    ConfusionMatrixDisplay.from_predictions(test.is_late, probability >= threshold,
                                            display_labels=["No prazo", "Atraso"], colorbar=False)
    plt.title(label)
    plt.tight_layout()
    plt.savefig(report_dir / "confusion_matrix.png", dpi=150)
    plt.close()
    PrecisionRecallDisplay.from_predictions(test.is_late, probability, name="Random Forest")
    plt.axhline(test.is_late.mean(), color="gray", linestyle="--", label="Prevalência no teste")
    plt.legend()
    plt.title(label)
    plt.tight_layout()
    plt.savefig(report_dir / "precision_recall.png", dpi=150)
    plt.close()
    importance.nlargest(12).sort_values().plot.barh(figsize=(9, 5))
    plt.title(f"{label}\nImportância por impureza (não é causalidade)")
    plt.tight_layout()
    plt.savefig(report_dir / "feature_importance.png", dpi=150)
    plt.close()
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
    print(json.dumps({"model_dir": str(model_dir), "source": source, "threshold": threshold,
                      "test": metadata["test"]}, indent=2))
    return metadata


def main():
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
