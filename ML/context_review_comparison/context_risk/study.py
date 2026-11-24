"""Réplicas temporais das três referências e comparação com/sem contexto."""
from pathlib import Path
import json,time,gc
import joblib,numpy as np,pandas as pd
from catboost import CatBoostClassifier
from lightgbm import LGBMClassifier
from sklearn.linear_model import LogisticRegression
from logipredict_final.features import feature_frame,encoder
from logipredict_final.experiment import (fit_base,fit_candidate,BASE_SPECS,split_at,
    cut_for_recall,metrics,DEV_STARTS)
from logipredict_final.refinements import fit_refined
from .runtime import MetaEstimator,meta_frame,reference_score

REFS=['modelo_631','modelo_564','modelo_614']
OOF_STARTS=pd.date_range('2017-10-01','2018-04-01',freq='MS')
SPECS=[dict(name='cb200_d4',kind='cb',trees=200,depth=4),
       dict(name='cb350_d6',kind='cb',trees=350,depth=6),
       dict(name='lgbm250_l15',kind='lgbm',trees=250),
       dict(name='lr_C005',kind='lr',C=.05)]
MAIN_RETENTION=.99
RETENTIONS=[1.,.99,.975,.95]

def fit_reference(name,data,start,end,old_oof):
    if name=='modelo_631':
        p,_,_,cal,future=fit_candidate('cascade_cb150_lr_hard3',data,start,end,old_oof,.9)
        return p,p.threshold,cal,future
    if name=='modelo_614':
        p,_,_,cal,future=fit_refined('blend_cb150_aft_extreme_0.5_3_0.5',data,start,end,.8)
        return p,p.threshold,cal,future
    _,cal,_,future=split_at(data,start,end,pd.Timestamp(start))
    # A main foi ajustada nos primeiros 60% e testada após 80% dos despachos.
    # A réplica usa 75% do passado disponível, purgando entregas ainda futuras.
    past=data.loc[data.dispatched_at.lt(pd.Timestamp(start))]
    cutoff=past.dispatched_at.iloc[int(len(past)*.75)]
    train=past.loc[past.dispatched_at.lt(cutoff)&past.delivered_at.lt(cutoff)]
    base=fit_base(BASE_SPECS[0],train,cutoff)
    # Pipeline simples, sem a regra nova de vencimento, para reproduzir a política original.
    from logipredict_final.runtime import CandidatePipeline
    class_threshold=.36999999999999994
    return base,class_threshold,cal,future

def score_reference(reference,rows):
    # BaseModel retorna score; os outros objetos são pipelines completos.
    if hasattr(reference,'raw_score') and not hasattr(reference,'predict_proba'):
        return reference.raw_score(feature_frame(rows))
    return reference_score(reference,rows)

def generate_oof(data,work,log=print):
    work=Path(work)
    original=joblib.load(work.parent/'training_inputs/reference_oof.joblib');records=[];folds={}
    for name in REFS:
        for start in OOF_STARTS:
            began=time.perf_counter();end=start+pd.DateOffset(months=1)
            reference,threshold,cal,future=fit_reference(name,data,start,end,original)
            p=score_reference(reference,future);cp=score_reference(reference,cal)
            records.append(pd.DataFrame({'index':future.index,'start':str(start),
                'reference':name,'score':p,'threshold':threshold,'alert':p>=threshold}))
            if start.strftime('%Y-%m-%d') in DEV_STARTS:
                test_start=data.dispatched_at.iloc[int(len(data)*.8)]
                available=future.label_known_at.lt(test_start).to_numpy()
                folds[(name,start.strftime('%Y-%m-%d'))]=dict(cal_index=cal.index.to_numpy(),
                    future_index=future.index[available].to_numpy(),cal_score=cp,future_score=p[available],threshold=threshold)
            log(f'OOF {name} {start.date()}: {len(future)} pedidos, {time.perf_counter()-began:.1f}s',flush=True)
            del reference;gc.collect()
            joblib.dump(dict(records=pd.concat(records,ignore_index=True),folds=folds),work/'oof.joblib',compress=3)
    return pd.concat(records,ignore_index=True),folds

def fit_meta(spec,x,y):
    x=x.copy()
    if spec['kind']=='cb':
        cats=x.select_dtypes(include=['object','string']).columns.tolist()
        for c in cats:x[c]=x[c].fillna('UNKNOWN').astype(str)
        model=CatBoostClassifier(iterations=spec['trees'],depth=spec['depth'],learning_rate=.04,
            l2_leaf_reg=25.,cat_features=cats,random_seed=42,thread_count=4,
            allow_writing_files=False,verbose=False)
        model.fit(x,y)
        return MetaEstimator(model,None,'cb',x.columns.tolist())
    prep=encoder(x,scale=spec['kind']=='lr');z=prep.fit_transform(x)
    if spec['kind']=='lr':model=LogisticRegression(C=spec['C'],max_iter=1000,random_state=42)
    else:model=LGBMClassifier(n_estimators=spec['trees'],num_leaves=15,learning_rate=.04,
        min_child_samples=80,reg_lambda=25.,n_jobs=4,random_state=42,verbosity=-1,
        deterministic=True,force_col_wise=True)
    model.fit(z,y)
    return MetaEstimator(model,prep,spec['kind'],x.columns.tolist())

def pool_for(data,context,oof,name,start,mode,use_context):
    selected=oof.loc[oof.reference.eq(name)&pd.to_datetime(oof.start).lt(pd.Timestamp(start))].copy()
    rows=data.loc[selected['index']]
    keep=(rows.dispatched_at.lt(pd.Timestamp(start)-pd.Timedelta(days=35))&rows.label_known_at.lt(pd.Timestamp(start))).to_numpy()
    if mode=='filter':keep &= selected.alert.to_numpy()
    selected=selected.loc[keep];rows=data.loc[selected['index']]
    x=meta_frame(rows,selected.score.to_numpy(),selected.threshold.to_numpy(),context.loc[rows.index] if use_context else None)
    assert rows.dispatched_at.max()<pd.Timestamp(start)-pd.Timedelta(days=35)
    assert rows.label_known_at.max()<pd.Timestamp(start)
    return x,rows.is_late.to_numpy()

def operate(y,p,base_score,base_cut,mode,retention=MAIN_RETENTION):
    y=np.asarray(y);gate=np.asarray(base_score)>=base_cut
    if mode=='filter':
        positives=gate&(y==1)
        if not positives.any():return 0.
        # Corte mais alto que preserva a fração declarada dos atrasos já encontrados.
        return cut_for_recall(y[gate],p[gate],retention)
    target=float((gate&(y==1)).sum()/max((y==1).sum(),1))
    return cut_for_recall(y,p,max(target,1e-8))

def evaluate_fold(data,context,fold,model,use_context,mode):
    cal=data.loc[fold['cal_index']];future=data.loc[fold['future_index']]
    xc=meta_frame(cal,fold['cal_score'],fold['threshold'],context.loc[cal.index] if use_context else None)
    xf=meta_frame(future,fold['future_score'],fold['threshold'],context.loc[future.index] if use_context else None)
    cp=model.predict_proba(xc)[:,1];p=model.predict_proba(xf)[:,1]
    cut=operate(cal.is_late,cp,fold['cal_score'],fold['threshold'],mode)
    if mode=='filter':p=np.where(fold['future_score']>=fold['threshold'],p,0.)
    row=metrics(future.is_late,p,cut)
    old=metrics(future.is_late,fold['future_score'],fold['threshold'])
    keep=row['TP']/max(old['TP'],1);fp_ratio=row['FP']/max(old['FP'],1)
    row.update(base_TP=old['TP'],base_FP=old['FP'],retention=keep,FP_ratio=fp_ratio,threshold=cut,
        objective=(fp_ratio+20*max(0,.98-keep) if mode=='filter'
                   else row['FPR']+5*max(0,old['recall']-row['recall'])))
    return row

def run_development(data,context,work,log=print):
    work=Path(work);o=joblib.load(work/'oof.joblib');oof,folds=o['records'],o['folds'];records=[]
    for name in REFS:
        for mode in ['rescore','filter']:
            for spec in SPECS:
                for start in DEV_STARTS:
                    x,y=pool_for(data,context,oof,name,start,mode,True)
                    model=fit_meta(spec,x,y)
                    row=evaluate_fold(data,context,folds[(name,start)],model,True,mode)
                    row.update(reference=name,mode=mode,spec=spec['name'],start=start,context=True)
                    records.append(row)
                    log(f'DEV {name} {mode} {spec["name"]} {start}: TP={row["TP"]}, FP={row["FP"]}',flush=True)
                    joblib.dump(records,work/'development_records.joblib')
                    del model;gc.collect()
    table=pd.DataFrame(records)
    summary=table.groupby(['reference','mode','spec']).agg(objective=('objective','mean'),std=('objective','std'),
        retention=('retention','mean'),FP_ratio=('FP_ratio','mean'),recall=('recall','mean'))
    summary['selection_score']=summary.objective+.25*summary['std'].fillna(0)
    summary=summary.sort_values('selection_score')
    chosen={}
    for name in REFS:
        for mode in ['rescore','filter']:
            chosen[(name,mode)]=summary.loc[(name,mode)].sort_values('selection_score').index[0]
    joblib.dump(dict(records=table,summary=summary,chosen=chosen),work/'selection.joblib')
    summary.to_csv(work/'development_summary.csv')
    frozen=[dict(reference=k[0],mode=k[1],spec=v) for k,v in chosen.items()]
    (work/'frozen_selection.json').write_text(json.dumps(frozen,indent=2),encoding='utf-8')
    return table,summary,chosen
