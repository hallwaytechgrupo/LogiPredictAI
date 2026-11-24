"""Homologação isolada; sem identidade completa conserva a previsão de referência."""
import os,json
from pathlib import Path
from contextlib import asynccontextmanager
import joblib,pandas as pd
from fastapi import FastAPI,HTTPException
from pydantic import Field,field_validator
from logipredict_final.contract import Shipment
from .runtime import reference_score,DoubleReviewPipeline

class ContextShipment(Shipment):
    seller_id: str|None=Field(default=None,min_length=1,max_length=128)
    origin_prefix5: str|None=Field(default=None,pattern=r'^\d{5}$')
    destination_prefix5: str|None=Field(default=None,pattern=r'^\d{5}$')

def create_app(model_dir=None):
    directory=Path(model_dir or os.environ.get('MODEL_DIR',Path(__file__).resolve().parents[1]/'novos_modelos/modelo_614_rescore'))
    @asynccontextmanager
    async def lifespan(app):
        app.state.bundle=joblib.load(directory/'model.joblib') if (directory/'model.joblib').exists() else None
        yield
    app=FastAPI(title='LogiPredict — comparação de contexto',lifespan=lifespan)
    def bundle():
        if app.state.bundle is None:raise HTTPException(503,'Selecione uma pasta com model.joblib exportado.')
        return app.state.bundle
    @app.get('/health')
    def health():
        m=bundle()['metadata'];return dict(status='ok',model_version=m['version'],synthetic=False)
    @app.get('/model')
    def model():return bundle()['metadata']
    @app.post('/predict')
    def predict(shipment:ContextShipment):
        b=bundle();m=b['metadata'];pipeline=b['pipeline'];rows=pd.DataFrame([shipment.model_dump()])
        missing=any(getattr(shipment,c) is None for c in ['seller_id','origin_prefix5','destination_prefix5'])
        warnings=['Score não calibrado; pesquisa retrospectiva com Olist 2016–2018.',
                  'Modelo candidato, sem confirmação em operação atual.']
        if missing:
            first=pipeline.first_stage if isinstance(pipeline,DoubleReviewPipeline) else pipeline
            p=float(reference_score(first.reference,rows)[0]);threshold=first.reference_threshold
            warnings.append('Identidade do vendedor ou prefixos CEP ausentes: usada a referência preservada, sem inventar histórico.')
            source='reference_missing_context'
        else:
            p=float(pipeline.predict_proba(rows)[0,1]);threshold=pipeline.threshold;source='context_model'
        return dict(model_version=m['version'],source='olist',synthetic=False,delay_probability=p,
                    threshold=float(threshold),predicted_late=bool(p>=threshold),warnings=warnings,
                    decision_source=source)
    return app

app=create_app()
