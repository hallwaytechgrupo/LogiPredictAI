"""Serviço opcional de homologação. A aplicação atual permanece intacta."""
import os,json
from pathlib import Path
from contextlib import asynccontextmanager
import joblib,pandas as pd
from fastapi import FastAPI,HTTPException
from .contract import Shipment
from .features import feature_frame


def create_app(model_dir=None):
    directory=Path(model_dir or os.environ.get('MODEL_DIR',Path(__file__).resolve().parents[1]/'release'))
    @asynccontextmanager
    async def lifespan(app):
        app.state.bundle=joblib.load(directory/'model.joblib') if (directory/'model.joblib').exists() else None
        yield
    app=FastAPI(title='LogiPredict — candidato de homologação',lifespan=lifespan)
    def bundle():
        if app.state.bundle is None:
            raise HTTPException(503,'Modelo ausente. Execute o notebook para exportar o candidato.')
        return app.state.bundle
    @app.get('/health')
    def health():
        m=bundle()['metadata']
        return dict(status='ok',model_version=m['version'],synthetic=m['synthetic'])
    @app.get('/model')
    def model():
        return bundle()['metadata']
    @app.get('/analytics/states')
    def states():
        bundle()
        return json.loads((directory/'analytics.json').read_text(encoding='utf-8'))
    @app.post('/predict')
    def predict(shipment:Shipment):
        b=bundle();m=b['metadata'];x=feature_frame(pd.DataFrame([shipment.model_dump()]))
        p=float(b['pipeline'].predict_proba(x)[0,1]);overdue=bool(x.remaining_days.iloc[0]<0)
        warnings=['Estimativa retrospectiva treinada com Olist 2016–2018; validar em operação recente.',
                  'Modelo candidato; não representa garantia de entrega nem validação externa.']
        if overdue:
            warnings.append('Prazo já vencido no despacho: sinalização por regra, não antecipação do modelo.')
        if any(getattr(shipment,c) is None for c in ['distance_km','total_weight_g','total_volume_cm3']):
            warnings.append('Atributos ausentes preenchidos com estatísticas do treino.')
        if shipment.sellers_count>1:
            warnings.append('Previsão agregada por pedido; não individualiza os pacotes.')
        return dict(model_version=m['version'],source=m['source'],synthetic=m['synthetic'],
                    delay_probability=p,threshold=m['threshold'],predicted_late=bool(p>=m['threshold']),
                    warnings=warnings,decision_source='already_overdue_rule' if overdue else 'model')
    return app

app=create_app()
