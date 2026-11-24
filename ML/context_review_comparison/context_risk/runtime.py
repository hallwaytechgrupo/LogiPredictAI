"""Combina o modelo preservado e um revisor com informações complementares."""
from dataclasses import dataclass
import numpy as np
import pandas as pd
from logipredict_final.features import feature_frame,enrich
from logipredict_final.runtime import logit

def reference_score(pipeline,rows):
    return pipeline.predict_proba(feature_frame(rows))[:,1]

def meta_frame(rows,score,threshold,context=None):
    x=enrich(feature_frame(rows))
    x['reference_logit']=logit(score)
    x['reference_margin']=logit(score)-logit(threshold)
    x['reference_alert']=(np.asarray(score)>=np.asarray(threshold)).astype(float)
    if context is not None:x=pd.concat([x,context],axis=1)
    return x

@dataclass
class MetaEstimator:
    model: object
    prep: object=None
    kind: str='cb'
    columns: object=None

    def predict_proba(self,x):
        x=x[self.columns].copy()
        if self.kind=='cb':
            for c in x.select_dtypes(include=['object','string']):x[c]=x[c].fillna('UNKNOWN').astype(str)
            x=x.replace([np.inf,-np.inf],np.nan)
        else:x=self.prep.transform(x)
        p=np.clip(self.model.predict_proba(x)[:,1],1e-10,1-1e-10)
        return np.column_stack([1-p,p])

@dataclass
class ContextPipeline:
    reference: object
    reference_threshold: float
    reviewer: MetaEstimator
    threshold: float
    history: object
    use_context: bool=True
    filter_only: bool=False
    history_cutoff: object=None

    def predict_proba(self,rows):
        score=reference_score(self.reference,rows)
        context=self.history.query(rows,self.history_cutoff) if self.use_context else None
        x=meta_frame(rows,score,self.reference_threshold,context)
        p=self.reviewer.predict_proba(x)[:,1]
        remaining=(pd.to_datetime(rows.estimated_delivery_at).dt.normalize()-pd.to_datetime(rows.dispatched_at).dt.normalize()).dt.days.to_numpy()
        overdue=remaining<0
        if self.filter_only:
            gate=score>=self.reference_threshold
            p=np.where(~gate,0.,p)
            p=np.where(overdue&gate,1.,p)
        else:p=np.where(overdue,1.,p)
        assert np.isfinite(p).all()
        return np.column_stack([1-p,p])

    def predict(self,rows):return (self.predict_proba(rows)[:,1]>=self.threshold).astype(int)


@dataclass
class DoubleReviewPipeline:
    """Modelo 614 -> contexto -> revisão adicional somente dos alertas enriquecidos."""
    first_stage: ContextPipeline
    reviewer: MetaEstimator
    threshold: float

    def predict_proba(self,rows):
        p=self.first_stage.predict_proba(rows)[:,1]
        context=self.first_stage.history.query(rows,self.first_stage.history_cutoff)
        raw=reference_score(self.first_stage.reference,rows)
        x=meta_frame(rows,raw,self.first_stage.reference_threshold,context)
        x['context_logit']=logit(p)
        x['context_margin']=logit(p)-logit(self.first_stage.threshold)
        q=self.reviewer.predict_proba(x)[:,1]
        gate=p>=self.first_stage.threshold
        q=np.where(gate,q,0.)
        remaining=(pd.to_datetime(rows.estimated_delivery_at).dt.normalize()-pd.to_datetime(rows.dispatched_at).dt.normalize()).dt.days.to_numpy()
        q=np.where((remaining<0)&gate,1.,q)
        return np.column_stack([1-q,q])

    def predict(self,rows):return (self.predict_proba(rows)[:,1]>=self.threshold).astype(int)
