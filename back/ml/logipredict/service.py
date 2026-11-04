"""Serviço interno: carrega somente artefatos locais produzidos pelo treinamento.

Expõe uma API FastAPI com os seguintes endpoints:
- GET /health: Verifica se o modelo está carregado e retorna a versão.
- GET /model: Retorna os metadados do modelo (features, parâmetros, limiar).
- GET /analytics/states: Retorna a taxa de atraso histórica por UF.
- POST /predict: Recebe um pedido (Shipment) e retorna a probabilidade de atraso.

O modelo é carregado uma vez na inicialização a partir do arquivo model.joblib
gerado pelo módulo train. Não aceita uploads de modelo em tempo de execução.
"""
import json
import os
from contextlib import asynccontextmanager
from pathlib import Path

import joblib
import pandas as pd
from fastapi import FastAPI, HTTPException

from .schema import Shipment, feature_frame


def create_app(model_dir=None):
    """Cria e configura a aplicação FastAPI com o modelo carregado.

    Args:
        model_dir: Caminho para o diretório com model.joblib e analytics.json.
                   Se None, usa a variável de ambiente MODEL_DIR ou "models/olist".

    Returns:
        Instância FastAPI configurada com os endpoints de previsão.
    """
    directory = Path(model_dir or os.getenv("MODEL_DIR", "models/olist"))

    @asynccontextmanager
    async def lifespan(app):
        """Carrega o modelo e os dados analíticos na inicialização do servidor.

        O modelo é carregado uma única vez em memória. Se o arquivo não existir,
        os endpoints retornam 503 (Service Unavailable) até que o treino seja executado.
        """
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
        """Retorna o modelo carregado ou levanta HTTP 503 se ausente."""
        if app.state.bundle is None:
            raise HTTPException(503, "Modelo ausente. Execute o treinamento e reinicie o serviço.")
        return app.state.bundle

    @app.get("/health")
    def health():
        """Endpoint de saúde: verifica se o modelo está carregado e acessível."""
        loaded = bundle()
        return {"status": "ok", "model_version": loaded["metadata"]["version"],
                "synthetic": loaded["metadata"]["synthetic"]}

    @app.get("/model")
    def model():
        """Retorna os metadados completos do modelo: versão, features, parâmetros, limiar."""
        return bundle()["metadata"]

    @app.get("/analytics/states")
    def states():
        """Retorna a taxa de atraso histórica observada por UF do cliente.

        Dados calculados durante o treino a partir dos registros reais.
        """
        bundle()
        if app.state.analytics is None:
            raise HTTPException(503, "Relatório histórico indisponível.")
        return app.state.analytics

    @app.post("/predict")
    def predict(shipment: Shipment):
        """Prevê a probabilidade de atraso para um pedido individual.

        Recebe um objeto Shipment validado pelo Pydantic, calcula as features
        temporais e retorna a probabilidade de atraso junto com avisos contextuais.

        O aviso "Score não calibrado" indica que a probabilidade é uma saída
        bruta do modelo e pode não refletir a frequência real de atrasos.

        Args:
            shipment: Dados do pedido validados pelo modelo Shipment.

        Returns:
            Dicionário com delay_probability, predicted_late, threshold, warnings.
        """
        loaded = bundle()
        features = feature_frame(pd.DataFrame([shipment.model_dump()]))
        probability = float(loaded["pipeline"].predict_proba(features)[0, 1])
        metadata = loaded["metadata"]

        # Constrói lista de avisos contextuais para o consumidor da API.
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


# Instância padrão para execução direta (uvicorn logipredict.service:app).
app = create_app()