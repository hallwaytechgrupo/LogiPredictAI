"""Inferência não gera dados. Informa quando o revisor foi treinado com SMOTENC."""
import os
from pathlib import Path
from contextlib import asynccontextmanager
import joblib,pandas as pd
from fastapi import FastAPI,HTTPException
from context_risk.service import ContextShipment
from context_risk.runtime import reference_score

def create_app(model_dir=None):
    directory=Path(model_dir or os.environ.get('MODEL_DIR',Path(__file__).resolve().parents[1]/'preservados/base_564'))
    @asynccontextmanager
    async def lifespan(app):
        app.state.bundle=joblib.load(directory/'model.joblib') if (directory/'model.joblib').exists() else None
        yield
    app=FastAPI(title='LogiPredict — comparação de amostragem',lifespan=lifespan)
    def bundle():
        if app.state.bundle is None:raise HTTPException(503,'Selecione um modelo exportado.')
        return app.state.bundle
    @app.get('/health')
    def health():
        m=bundle()['metadata'];return dict(status='ok',model_version=m['version'],synthetic=bool(m['synthetic']))
    @app.get('/model')
    def model():return bundle()['metadata']
    @app.post('/predict')
    def predict(shipment:ContextShipment):
        b=bundle();pmodel=b['pipeline'];m=b['metadata'];rows=pd.DataFrame([shipment.model_dump()])
        missing=any(getattr(shipment,c) is None for c in ['seller_id','origin_prefix5','destination_prefix5'])
        warnings=['Score não calibrado; estudo retrospectivo com Olist 2016–2018.']
        if missing:
            p=float(reference_score(pmodel.reference,rows)[0]);cut=pmodel.reference_threshold;synthetic=False
            warnings.append('Identidades ausentes: usada somente a etapa de referência, sem o revisor contextual.')
            decision_source='reference_missing_context'
        else:
            p=float(pmodel.predict_proba(rows)[0,1]);cut=pmodel.threshold;synthetic=bool(m['synthetic'])
            decision_source='reviewer'
            if synthetic:warnings.append('Revisor experimental treinado também com vetores artificiais SMOTENC; não são entregas observadas.')
        return dict(model_version=m['version'],source='olist',synthetic=synthetic,delay_probability=p,
            threshold=float(cut),predicted_late=bool(p>=cut),warnings=warnings,decision_source=decision_source,
            training_augmentation_used=synthetic)
    return app

app=create_app()
