"""Serviço interno: carrega somente artefatos locais produzidos pelo treinamento."""
import json
import os
from contextlib import asynccontextmanager
from pathlib import Path

import joblib
import pandas as pd
from fastapi import FastAPI, HTTPException

from .schema import Shipment, feature_frame


def create_app(model_dir=None):
    directory = Path(model_dir or os.getenv("MODEL_DIR", "models/olist"))

    @asynccontextmanager
    async def lifespan(app):
        app.state.bundle = None
        app.state.analytics = None
        model_file = directory / "model.joblib"
        if model_file.exists():
            # joblib usa pickle. Nunca carregar arquivos enviados por usuários ou de origem desconhecida.
            app.state.bundle = joblib.load(model_file)
            analytics_file = directory / "analytics.json"
            if analytics_file.exists():
                app.state.analytics = json.loads(analytics_file.read_text(encoding="utf-8"))
        yield

    app = FastAPI(title="LogiPredict ML — serviço interno", version="0.1.0", lifespan=lifespan)

    def bundle():
        if app.state.bundle is None:
            raise HTTPException(503, "Modelo ausente. Execute o treinamento e reinicie o serviço.")
        return app.state.bundle

    @app.get("/health")
    def health():
        loaded = bundle()
        return {"status": "ok", "model_version": loaded["metadata"]["version"],
                "synthetic": loaded["metadata"]["synthetic"]}

    @app.get("/model")
    def model():
        return bundle()["metadata"]

    @app.get("/analytics/states")
    def states():
        bundle()
        if app.state.analytics is None:
            raise HTTPException(503, "Relatório histórico indisponível.")
        return app.state.analytics

    @app.post("/predict")
    def predict(shipment: Shipment):
        loaded = bundle()
        features = feature_frame(pd.DataFrame([shipment.model_dump()]))
        probability = float(loaded["pipeline"].predict_proba(features)[0, 1])
        metadata = loaded["metadata"]
        warnings = []
        if metadata["synthetic"]:
            warnings.append("Modelo de demonstração treinado com dados sintéticos.")
        if any(getattr(shipment, col) is None for col in ["distance_km", "total_weight_g", "total_volume_cm3"]):
            warnings.append("Atributos ausentes preenchidos com estatísticas do treino.")
        if shipment.sellers_count > 1:
            warnings.append("Previsão agregada por pedido; não individualiza pacotes de vários vendedores.")
        warnings.append("Score não calibrado; validar antes de uso operacional.")
        return {"model_version": metadata["version"], "source": metadata["source"],
                "synthetic": metadata["synthetic"], "delay_probability": probability,
                "threshold": metadata["threshold"], "predicted_late": probability >= metadata["threshold"],
                "warnings": warnings}

    return app


app = create_app()
