"""Objetos serializáveis compatíveis com o pipeline carregado pela main."""
from dataclasses import dataclass
import numpy as np
from scipy.special import expit, ndtr
from .features import enrich

def logit(p):
    p = np.clip(np.asarray(p, dtype=float), 1e-7, 1-1e-7)
    return np.log(p/(1-p))

def survival_probability(mu, remaining_days, distribution, scale):
    # T = dias de calendário até a entrega + 1. A translação evita duração zero.
    # T > prazo+1 equivale exatamente ao rótulo entrega_data > promessa_data.
    boundary = np.maximum(np.asarray(remaining_days, dtype=float)+1, 1e-6)
    z = (np.log(boundary)-np.asarray(mu))/scale
    if distribution == "normal":
        return ndtr(-z)
    if distribution == "logistic":
        return expit(-z)
    if distribution == "extreme":
        return np.exp(-np.exp(np.clip(z, -40, 40)))
    raise ValueError(distribution)

@dataclass
class BaseModel:
    preprocessor: object
    model: object
    kind: str
    derived: bool = True
    distribution: str = "normal"
    scale: float = 1.

    def raw_score(self, frame):
        data = enrich(frame, self.derived)
        x = self.preprocessor.transform(data)
        if self.kind == "aft":
            import xgboost as xgb
            mu = self.model.predict(xgb.DMatrix(x), output_margin=True)
            return survival_probability(mu, frame.remaining_days, self.distribution, self.scale)
        if self.kind == "hgb":
            x = x.toarray() if hasattr(x, "toarray") else x
        if self.kind == "duration":
            # Regressão estima dias de calendário; o score ordena a folga no prazo.
            return expit((self.model.predict(x)-frame.remaining_days.to_numpy())/5.)
        return self.model.predict_proba(x)[:, 1]


@dataclass
class BlendModel:
    """Combina scores calibrados no passado, sem reajustar no período final."""
    models: list
    calibrators: list
    weights: list
    kind: str = 'blend'

    def raw_score(self, frame):
        transformed=[]
        for base,calibrator in zip(self.models,self.calibrators):
            p=base.raw_score(frame)
            q=calibrator.predict_proba(logit(p).reshape(-1,1))[:,1]
            transformed.append(logit(q))
        return expit(np.average(transformed,axis=0,weights=self.weights))

@dataclass
class CandidatePipeline:
    base: BaseModel
    threshold: float
    calibration: object = None
    verifier: object = None
    detector_cut: float = None
    verifier_cut: float = None
    negative_reference: object = None
    classes_ = np.array([0, 1])

    def components(self, frame):
        base_score = self.base.raw_score(frame)
        if self.verifier is None:
            raw = logit(base_score).reshape(-1, 1)
            score = (self.calibration.predict_proba(raw)[:, 1]
                     if self.calibration is not None else base_score)
            return score, base_score, None
        v = verifier_frame(frame, base_score, self.negative_reference)
        verify_score = self.verifier.predict_proba(v)[:, 1]
        margin = np.minimum(logit(base_score)-logit(self.detector_cut),
                            logit(verify_score)-logit(self.verifier_cut))
        score = self.calibration.predict_proba(margin.reshape(-1, 1))[:, 1]
        # Preserva a conjunção dos dois cortes mesmo em empates de arredondamento.
        score = np.where((margin<0)&(score>=self.threshold), np.nextafter(self.threshold, 0.), score)
        score = np.where((margin>=0)&(score<self.threshold), self.threshold, score)
        return score, base_score, verify_score

    def predict_proba(self, frame):
        score, _, _ = self.components(frame)
        score = np.asarray(score, dtype=float)
        score = np.where(frame.remaining_days.to_numpy()<0, 1., score)
        if not np.isfinite(score).all():
            raise ValueError("Modelo retornou score não finito")
        score = np.clip(score, 0., 1.)
        return np.column_stack([1-score, score])

    def predict(self, frame):
        return (self.predict_proba(frame)[:, 1]>=self.threshold).astype(int)

def verifier_frame(frame, probability, negative_reference):
    x = enrich(frame)
    x["detector_logit"] = logit(probability)
    reference = np.sort(np.asarray(negative_reference))
    x["detector_percentile"] = np.searchsorted(reference, probability, side="right")/max(len(reference), 1)
    return x
