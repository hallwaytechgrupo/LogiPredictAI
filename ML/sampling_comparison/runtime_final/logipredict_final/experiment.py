"""Comparação temporal de classificadores, sobrevivência e verificação de alertas."""
from pathlib import Path
import copy
import hashlib
import json
import time
import gc
import joblib
import numpy as np
import pandas as pd
import xgboost as xgb
from catboost import CatBoostClassifier
from lightgbm import LGBMClassifier
from sklearn.ensemble import RandomForestClassifier, HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import confusion_matrix, roc_curve, roc_auc_score, average_precision_score
from sklearn.pipeline import make_pipeline
from .data import load_orders
from .features import feature_frame, enrich, encoder
from .runtime import BaseModel, CandidatePipeline, verifier_frame, logit

SEED = 42
THREADS = 4
TARGETS = (.80, .90, .95)
PRIMARY_TARGET = .90
SCAN_TARGET = .975
DEV_STARTS = ['2017-12-01','2018-02-01','2018-03-01','2018-04-01']
OOF_STARTS = pd.date_range('2017-08-01','2018-04-01',freq='MS')
BASE_SPECS = [
    dict(name='rf_main',kind='rf',trees=250,derived=False),
    dict(name='cb150',kind='cb',trees=150,weight=1.,derived=True),
    dict(name='cb300_peso3',kind='cb',trees=300,weight=3.,derived=True),
    dict(name='lgbm400',kind='lgbm',trees=400,weight=1.,derived=True),
    dict(name='xgb400',kind='xgb',trees=400,depth=3,weight=1.,derived=True),
    dict(name='xgb500_peso3',kind='xgb',trees=500,depth=5,weight=3.,derived=True),
    dict(name='hgb250',kind='hgb',trees=250,derived=True),
]
DETECTORS = [BASE_SPECS[0], BASE_SPECS[1]]
VERIFY_SPECS = [
    dict(name='lr_hard3',kind='lr',C=.01,positive=10.,hard=3.),
    dict(name='lr_hard1',kind='lr',C=.1,positive=10.,hard=1.),
    dict(name='lgbm_hard3',kind='lgbm',trees=120,leaves=7,positive=10.,hard=3.),
    dict(name='lgbm_hard1',kind='lgbm',trees=180,leaves=15,positive=5.,hard=1.),
]
AFT_SPECS = [dict(name=f'aft_{dist}_{scale}_{depth}',kind='aft',distribution=dist,
                 scale=scale,depth=depth,trees=350,derived=True)
             for dist in ['normal','logistic','extreme'] for scale in [.5,1.,1.5] for depth in [3,5]]

def cut_for_recall(y, score, target):
    _, recall, cuts = roc_curve(y, score, drop_intermediate=False)
    ids = np.flatnonzero(recall>=target)
    if not len(ids):
        raise ValueError('Não foi possível definir o corte de recall.')
    return float(cuts[ids[0]])

def metrics(y, score, threshold):
    y=np.asarray(y,dtype=int);score=np.asarray(score,dtype=float)
    tn,fp,fn,tp=confusion_matrix(y,score>=threshold,labels=[0,1]).ravel()
    return dict(TP=int(tp),FP=int(fp),FN=int(fn),TN=int(tn),
                recall=float(tp/max(tp+fn,1)),precision=float(tp/max(tp+fp,1)),
                FPR=float(fp/max(fp+tn,1)),ROC_AUC=float(roc_auc_score(y,score)),
                AP=float(average_precision_score(y,score)))

def split_at(data,start,end,selection_cut):
    start=pd.Timestamp(start);end=pd.Timestamp(end)
    cal_start=start-pd.Timedelta(days=35);cal_end=start-pd.Timedelta(days=14)
    proactive=~data.already_overdue
    before=data.dispatched_at.lt(start)&proactive
    in_cal=data.dispatched_at.between(cal_start,cal_end,inclusive='left')
    # Bloco de calibração é retirado do ajuste. Outros pedidos conhecidos até E
    # podem ser mais recentes; somente a janela DEPOIS de E é o teste futuro.
    train=data.loc[before&~in_cal].copy()
    cal_all=data.loc[before&in_cal].copy()
    cal=cal_all.loc[cal_all.label_known_at<start].copy()
    future=data.loc[data.dispatched_at.between(start,end,inclusive='left')&proactive].copy()
    if end<=selection_cut:
        future=future.loc[future.label_known_at<selection_cut]
    assert set(train.order_id).isdisjoint(cal_all.order_id)
    assert set(train.order_id).isdisjoint(future.order_id)
    assert train.dispatched_at.max()<start and cal.label_known_at.max()<start
    return train,cal,cal_all,future

def fit_base(spec,train,asof):
    asof=pd.Timestamp(asof)
    fit=train if spec['kind']=='aft' else train.loc[train.label_known_at<asof]
    x=feature_frame(fit);derived=spec.get('derived',True)
    z=enrich(x,derived);prep=encoder(z);matrix=prep.fit_transform(z)
    kind=spec['kind']
    if kind=='rf':
        model=RandomForestClassifier(n_estimators=spec['trees'],max_depth=16,min_samples_leaf=5,
                    class_weight='balanced_subsample',n_jobs=THREADS,random_state=SEED)
    elif kind=='cb':
        model=CatBoostClassifier(iterations=spec['trees'],depth=6,learning_rate=.05,l2_leaf_reg=15.,
                    class_weights=[1,spec['weight']],random_seed=SEED,thread_count=THREADS,
                    allow_writing_files=False,verbose=False)
    elif kind=='lgbm':
        model=LGBMClassifier(n_estimators=spec['trees'],num_leaves=15,learning_rate=.04,
                    min_child_samples=80,reg_lambda=15.,scale_pos_weight=spec['weight'],
                    n_jobs=THREADS,random_state=SEED,verbosity=-1,deterministic=True,force_col_wise=True)
    elif kind=='xgb':
        model=xgb.XGBClassifier(n_estimators=spec['trees'],max_depth=spec['depth'],learning_rate=.04,
                    min_child_weight=30,reg_lambda=15.,scale_pos_weight=spec['weight'],
                    tree_method='hist',n_jobs=THREADS,random_state=SEED)
    elif kind=='hgb':
        model=HistGradientBoostingClassifier(max_iter=spec['trees'],max_leaf_nodes=15,
                    min_samples_leaf=80,learning_rate=.05,l2_regularization=15.,early_stopping=False,random_state=SEED)
        matrix=matrix.toarray() if hasattr(matrix,'toarray') else matrix
    elif kind=='aft':
        lower,upper=survival_bounds(fit,asof)
        dm=xgb.DMatrix(matrix)
        dm.set_float_info('label_lower_bound',lower);dm.set_float_info('label_upper_bound',upper)
        params=dict(objective='survival:aft',eval_metric='aft-nloglik',aft_loss_distribution=spec['distribution'],
                    aft_loss_distribution_scale=spec['scale'],max_depth=spec['depth'],eta=.04,
                    min_child_weight=30,reg_lambda=15.,tree_method='hist',nthread=THREADS,seed=SEED)
        model=xgb.train(params,dm,num_boost_round=spec['trees'],verbose_eval=False)
        return BaseModel(prep,model,kind,derived,spec['distribution'],spec['scale'])
    else:
        raise ValueError(kind)
    model.fit(matrix,fit.is_late)
    return BaseModel(prep,model,kind,derived)

def survival_bounds(frame,asof):
    """Observado=[T,T]; ainda sem entrega=[tempo observado,+infinito]."""
    asof=pd.Timestamp(asof)
    observed=frame.delivered_at.lt(asof).to_numpy()
    elapsed=(asof.normalize()-frame.dispatched_at.dt.normalize()).dt.days.to_numpy()+1.
    # O valor final de entrega só é lido para linhas concluídas antes do ajuste.
    lower=np.maximum(elapsed,1.)
    upper=np.full(len(frame),np.inf)
    lower[observed]=frame.loc[observed,'event_duration'].to_numpy()
    upper[observed]=lower[observed]
    assert (lower>0).all() and (upper>=lower).all()
    return lower,upper

def calibrated_base(base,cal,target):
    score=base.raw_score(feature_frame(cal))
    transform=LogisticRegression(C=1.,random_state=SEED).fit(logit(score).reshape(-1,1),cal.is_late)
    if transform.coef_[0,0]<=0:
        transform=None;probability=score
    else:
        probability=transform.predict_proba(logit(score).reshape(-1,1))[:,1]
    cut=cut_for_recall(cal.is_late,probability,target)
    return CandidatePipeline(base,cut,transform)

def train_verifier(spec,pool):
    x=pool.drop(columns=['y','weight'])
    prep=encoder(x,scale=spec['kind']=='lr')
    if spec['kind']=='lr':
        model=LogisticRegression(C=spec['C'],max_iter=1000,random_state=SEED)
    else:
        model=LGBMClassifier(n_estimators=spec['trees'],num_leaves=spec['leaves'],learning_rate=.04,
                    min_child_samples=60,reg_lambda=20.,n_jobs=THREADS,random_state=SEED,
                    verbosity=-1,deterministic=True,force_col_wise=True)
    pipeline=make_pipeline(prep,model)
    pipeline.fit(x,pool.y,**{pipeline.steps[-1][0]+'__sample_weight':pool.weight.to_numpy()})
    return pipeline

def cascade_pipeline(base,verifier,cal,target):
    x=feature_frame(cal);score=base.raw_score(x)
    detector_cut=cut_for_recall(cal.is_late,score,SCAN_TARGET)
    reference=np.sort(score[cal.is_late.eq(0)])
    v=verifier_frame(x,score,reference)
    ps=verifier.predict_proba(v)[:,1]
    # -1 representa somente a não seleção; não é uma probabilidade exportada.
    gated=np.where(score>=detector_cut,ps,-1.)
    verifier_cut=cut_for_recall(cal.is_late,gated,target)
    if not 0<=verifier_cut<=1:
        raise ValueError('Detector não preservou positivos suficientes na calibração.')
    margin=np.minimum(logit(score)-logit(detector_cut),logit(ps)-logit(verifier_cut))
    transform=LogisticRegression(C=1.,random_state=SEED).fit(margin.reshape(-1,1),cal.is_late)
    if transform.coef_[0,0]<=0:
        raise ValueError('A calibração da cascata inverteu a ordenação.')
    cut=float(transform.predict_proba(np.array([[0.]]))[0,1])
    return CandidatePipeline(base,cut,transform,verifier,detector_cut,verifier_cut,reference)

def build_pool(data,oof,start,spec):
    """Somente alarmes históricos fora do treino, com rótulo já conhecido."""
    cal_start=pd.Timestamp(start)-pd.Timedelta(days=35)
    lookup=data.set_index('order_id')
    rows=[]
    for record in oof:
        if pd.Timestamp(record['start'])>=pd.Timestamp(start):
            continue
        ids=record['future_ids'];df=lookup.loc[ids]
        keep=(df.dispatched_at<cal_start)&(df.label_known_at<pd.Timestamp(start))&record['scanned']
        if not keep.any():
            continue
        score=record['future_score'][keep.to_numpy()]
        actual=df.loc[keep]
        x=verifier_frame(feature_frame(actual),score,record['negative_reference'])
        x['y']=actual.is_late.to_numpy()
        # Negativos difíceis recebem mais peso; os positivos também são preservados.
        x['weight']=np.where(x.y.eq(1),spec['positive'],1+spec['hard']*x.detector_percentile)
        rows.append(x)
    if not rows:
        raise ValueError('Ainda não há previsões históricas para o verificador.')
    pool=pd.concat(rows,ignore_index=True)
    assert pool.y.nunique()==2
    return pool

def record_oof(base,cal,future,start):
    cs=base.raw_score(feature_frame(cal));fs=base.raw_score(feature_frame(future))
    cut=cut_for_recall(cal.is_late,cs,SCAN_TARGET)
    return dict(start=str(start),future_ids=future.order_id.tolist(),future_score=fs,
                scanned=fs>=cut,negative_reference=np.sort(cs[cal.is_late.eq(0)]),detector_cut=cut)

def candidate_record(name,family,start,future,pipeline,base_score=None):
    p=pipeline.predict_proba(feature_frame(future))[:,1]
    stat=metrics(future.is_late,p,pipeline.threshold)
    stat.update(name=name,family=family,start=str(start),threshold=pipeline.threshold,
                objective=stat['FPR']+5*max(0,PRIMARY_TARGET-stat['recall']))
    return stat

def run_development(data,work,log=print):
    """Orquestra os testes sem ler os rótulos do período final na seleção."""
    work=Path(work);work.mkdir(parents=True,exist_ok=True)
    test_start=data.dispatched_at.iloc[int(len(data)*.8)]
    records=[];oof_by_detector={};periods={}
    for detector in DETECTORS:
        oof=[]
        for start in OOF_STARTS:
            end=start+pd.DateOffset(months=1)
            train,cal,_,future=split_at(data,start,end,test_start)
            base=fit_base(detector,train,start)
            oof.append(record_oof(base,cal,future,start))
            log(f'OOF {detector["name"]}: {start.date()}, {len(future)} pedidos',flush=True)
            if start.strftime('%Y-%m-%d') in DEV_STARTS:
                periods[(detector['name'],start.strftime('%Y-%m-%d'))]=(base,cal,future)
        oof_by_detector[detector['name']]=oof
    joblib.dump(oof_by_detector,work/'oof.joblib')
    for spec in BASE_SPECS+AFT_SPECS:
        for start in DEV_STARTS:
            began=time.perf_counter();end=pd.Timestamp(start)+pd.DateOffset(months=1)
            train,cal,_,future=split_at(data,start,end,test_start)
            cached=periods.get((spec['name'],start))
            base=cached[0] if cached else fit_base(spec,train,start)
            pipeline=calibrated_base(base,cal,PRIMARY_TARGET)
            row=candidate_record(spec['name'],spec['kind'],start,future,pipeline)
            records.append(row)
            log(f'{spec["name"]} {start}: recall={row["recall"]:.3f}, FP={row["FP"]}, {time.perf_counter()-began:.1f}s',flush=True)
            joblib.dump(records,work/'development_records.joblib')
            if not cached:
                del base,pipeline;gc.collect()
    for detector in DETECTORS:
        for spec in VERIFY_SPECS:
            for start in DEV_STARTS:
                base,cal,future=periods[(detector['name'],start)]
                pool=build_pool(data,oof_by_detector[detector['name']],start,spec)
                verifier=train_verifier(spec,pool)
                pipeline=cascade_pipeline(base,verifier,cal,PRIMARY_TARGET)
                name=f'cascade_{detector["name"]}_{spec["name"]}'
                row=candidate_record(name,'cascade',start,future,pipeline)
                row['verifier_train_n']=len(pool);records.append(row)
                log(f'{name} {start}: recall={row["recall"]:.3f}, FP={row["FP"]}',flush=True)
                joblib.dump(records,work/'development_records.joblib')
    table=pd.DataFrame(records)
    summary=table.groupby(['name','family']).agg(objective=('objective','mean'),variation=('objective','std'),
            recall=('recall','mean'),FPR=('FPR','mean'),AP=('AP','mean'))
    summary['selection_score']=summary.objective+.25*summary.variation.fillna(0)
    summary=summary.sort_values('selection_score')
    summary.to_csv(work/'development_summary.csv')
    selected=dict(records=table,summary=summary,oof=oof_by_detector,test_start=test_start)
    joblib.dump(selected,work/'selection.joblib')
    joblib.dump(selected,work/'initial_selection.joblib')
    return table,summary,oof_by_detector

def spec_by_name(name):
    for spec in BASE_SPECS+AFT_SPECS:
        if spec['name']==name:
            return spec,None
    for detector in DETECTORS:
        for verifier in VERIFY_SPECS:
            if name==f'cascade_{detector["name"]}_{verifier["name"]}':
                return detector,verifier
    raise KeyError(name)

def fit_candidate(name,data,start,end,oof,target):
    spec,verify_spec=spec_by_name(name)
    train,cal,_,future=split_at(data,start,end,pd.Timestamp(start))
    base=fit_base(spec,train,start)
    verifier=None
    if verify_spec is not None:
        pool=build_pool(data,oof[spec['name']],start,verify_spec)
        verifier=train_verifier(verify_spec,pool)
        pipeline=cascade_pipeline(base,verifier,cal,target)
    else:
        pipeline=calibrated_base(base,cal,target)
    return pipeline,base,verifier,cal,future
