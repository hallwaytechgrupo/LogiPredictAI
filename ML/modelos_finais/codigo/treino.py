"""Reajuste opcional do filtro, com o primeiro detector mantido fixo."""
from pathlib import Path
import copy,json
import numpy as np
import pandas as pd
from catboost import CatBoostClassifier
from sklearn.metrics import roc_curve
from logipredict_final.data import load_orders
from logipredict_final.features import feature_frame
from context_risk.history import HistoryStore
from context_risk.runtime import meta_frame,MetaEstimator
from operacao import conferir_arquivo

def preparar_treino(pasta):
    """Reconstitui a base real e consulta o histórico no instante de cada despacho."""
    pasta=Path(pasta)
    conferir_arquivo(pasta,'dados/previsoes_temporais.csv.gz')
    conferir_arquivo(pasta,'dados/origem.json')
    dados,origem=load_orders()
    esperado=json.loads((pasta/'dados/origem.json').read_text(encoding='utf-8'))
    assert origem==esperado,'Os dados brutos diferem da base utilizada na avaliação registrada.'
    historico=HistoryStore.from_orders(dados)
    contexto=historico.query(dados)
    previsoes=pd.read_csv(pasta/'dados/previsoes_temporais.csv.gz',
        dtype={'reference':'string','order_id':'string'},parse_dates=['start'],float_precision='round_trip')
    assert set(previsoes.order_id).issubset(set(dados.order_id))
    return dados,historico,contexto,previsoes

def reajustar_filtro(modelo,metadados,pacote_treino,referencia,retencao):
    """Ajusta apenas o CatBoost revisor; não sobrescreve os pesos originais."""
    dados,historico,contexto,previsoes=pacote_treino
    instante=pd.Timestamp(metadados['trained_asof'])
    inicio_calibracao=instante-pd.Timedelta(days=35)
    fim_calibracao=instante-pd.Timedelta(days=14)
    indice=pd.Series(dados.index,index=dados.order_id)

    # As previsões históricas vieram de detectores ajustados antes do mês previsto.
    anteriores=previsoes.loc[previsoes.reference.eq(referencia)&previsoes.start.lt(instante)].copy()
    posicoes=indice.loc[anteriores.order_id].to_numpy()
    linhas=dados.loc[posicoes]
    elegiveis=(linhas.dispatched_at.lt(inicio_calibracao)&linhas.label_known_at.lt(instante)).to_numpy()
    anteriores=anteriores.loc[elegiveis]
    linhas=dados.loc[indice.loc[anteriores.order_id].to_numpy()]
    assert linhas.dispatched_at.max()<inicio_calibracao
    assert linhas.label_known_at.max()<instante

    # O filtro aprende com alertas verdadeiros e falsos já conhecidos naquela data.
    x=meta_frame(linhas,anteriores.score.to_numpy(),anteriores.threshold.to_numpy(),contexto.loc[linhas.index])
    y=linhas.is_late.to_numpy()
    categorias=x.select_dtypes(include=['object','string']).columns.tolist()
    for coluna in categorias:x[coluna]=x[coluna].fillna('UNKNOWN').astype(str)
    revisor=CatBoostClassifier(iterations=350,depth=6,learning_rate=.04,l2_leaf_reg=25.,
        cat_features=categorias,random_seed=42,thread_count=4,allow_writing_files=False,verbose=False)
    revisor.fit(x,y)
    estimador=MetaEstimator(revisor,None,'cb',x.columns.tolist())

    # A calibração usa pedidos reais de um bloco que ficou fora do ajuste.
    calibracao=dados.loc[dados.dispatched_at.ge(inicio_calibracao)&dados.dispatched_at.lt(fim_calibracao)
        &dados.label_known_at.lt(instante)&~dados.already_overdue]
    assert set(linhas.order_id).isdisjoint(calibracao.order_id)
    score_base=modelo.reference.predict_proba(feature_frame(calibracao))[:,1]
    atributos=meta_frame(calibracao,score_base,modelo.reference_threshold,contexto.loc[calibracao.index])
    score_filtro=estimador.predict_proba(atributos)[:,1]
    alertas=score_base>=modelo.reference_threshold
    _,sensibilidade,cortes=roc_curve(calibracao.is_late.to_numpy()[alertas],score_filtro[alertas],drop_intermediate=False)
    posicao=np.flatnonzero(sensibilidade>=retencao)[0]

    # O novo objeto mantém a primeira etapa e recebe somente o filtro reajustado.
    resultado=copy.copy(modelo)
    resultado.reviewer=estimador
    resultado.history=historico
    resultado.threshold=float(cortes[posicao])
    informacoes={'linhas_treino':len(x),'atrasos_treino':int(y.sum()),
        'linhas_calibracao':len(calibracao),'retencao_calibracao':retencao,
        'ultimo_despacho_treino':str(linhas.dispatched_at.max()),
        'ultimo_rotulo_conhecido':str(linhas.label_known_at.max()),'limiar':resultado.threshold}
    return resultado,informacoes
