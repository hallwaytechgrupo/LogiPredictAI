"""Revisão adicional: usa previsões temporais do modelo já enriquecido."""
from pathlib import Path
import gc,json
import joblib,numpy as np,pandas as pd
from logipredict_final.runtime import logit
from logipredict_final.experiment import metrics
from .runtime import meta_frame
from .study import (SPECS,DEV_STARTS,fit_reference,score_reference,fit_meta,pool_for,operate)

def add_context_score(x,p,cut):
    x=x.copy();x['context_logit']=logit(p);x['context_margin']=logit(p)-logit(cut)
    return x

def nested_pool(data,context,records,start):
    selected=records.loc[pd.to_datetime(records.start).lt(pd.Timestamp(start))].copy()
    rows=data.loc[selected['index']]
    keep=rows.dispatched_at.lt(pd.Timestamp(start)-pd.Timedelta(days=35))&rows.label_known_at.lt(pd.Timestamp(start))
    keep=keep.to_numpy()&selected.alert.to_numpy();selected=selected.loc[keep];rows=data.loc[selected['index']]
    x=meta_frame(rows,selected.base_score.to_numpy(),selected.base_cut.to_numpy(),context.loc[rows.index])
    x=add_context_score(x,selected.context_score.to_numpy(),selected.context_cut.to_numpy())
    return x,rows.is_late.to_numpy()

def run_double_development(data,context,work,log=print):
    work=Path(work);sel=joblib.load(work/'selection.joblib');o=joblib.load(work/'oof.joblib');oof=o['records'];folds=o['folds']
    spec=next(s for s in SPECS if s['name']==sel['chosen'][('modelo_614','rescore')])
    original=joblib.load(work.parent/'training_inputs/reference_oof.joblib')
    records=[];nested_folds={};test_start=data.dispatched_at.iloc[int(len(data)*.8)]
    for start in pd.date_range('2017-12-01','2018-04-01',freq='MS'):
        key=('modelo_614',start.strftime('%Y-%m-%d'))
        fold=folds.get(key)
        if fold is None:
            reference,cut,cal,future=fit_reference('modelo_614',data,start,start+pd.DateOffset(months=1),original)
            fold=dict(cal_index=cal.index.to_numpy(),future_index=future.index.to_numpy(),
                cal_score=score_reference(reference,cal),future_score=score_reference(reference,future),threshold=cut)
            del reference
        x,y=pool_for(data,context,oof,'modelo_614',start,'rescore',True)
        meta=fit_meta(spec,x,y);cal=data.loc[fold['cal_index']];future=data.loc[fold['future_index']]
        xc=meta_frame(cal,fold['cal_score'],fold['threshold'],context.loc[cal.index])
        xf=meta_frame(future,fold['future_score'],fold['threshold'],context.loc[future.index])
        cp=meta.predict_proba(xc)[:,1];p=meta.predict_proba(xf)[:,1]
        cut=operate(cal.is_late,cp,fold['cal_score'],fold['threshold'],'rescore')
        records.append(pd.DataFrame(dict(index=future.index,start=str(start),base_score=fold['future_score'],
            base_cut=fold['threshold'],context_score=p,context_cut=cut,alert=p>=cut)))
        nested_folds[start.strftime('%Y-%m-%d')]=dict(fold=fold,cal_context_score=cp,
            future_context_score=p,context_cut=cut)
        log(f'OOF adicional do modelo 614 com contexto: {start.date()}',flush=True)
        del meta;gc.collect()
    records=pd.concat(records,ignore_index=True)
    # Há passado suficiente para a terceira etapa somente a partir de fevereiro.
    results=[]
    for review_spec in [SPECS[2],SPECS[3]]:
        for start in ['2018-02-01','2018-03-01','2018-04-01']:
            x,y=nested_pool(data,context,records,start);model=fit_meta(review_spec,x,y)
            nested=nested_folds[start];fold=nested['fold'];cal=data.loc[fold['cal_index']];future=data.loc[fold['future_index']]
            xc=add_context_score(meta_frame(cal,fold['cal_score'],fold['threshold'],context.loc[cal.index]),nested['cal_context_score'],nested['context_cut'])
            xf=add_context_score(meta_frame(future,fold['future_score'],fold['threshold'],context.loc[future.index]),nested['future_context_score'],nested['context_cut'])
            cp=model.predict_proba(xc)[:,1];p=model.predict_proba(xf)[:,1]
            cut=operate(cal.is_late,cp,nested['cal_context_score'],nested['context_cut'],'filter')
            p=np.where(nested['future_context_score']>=nested['context_cut'],p,0.)
            stat=metrics(future.is_late,p,cut);old=metrics(future.is_late,nested['future_context_score'],nested['context_cut'])
            keep=stat['TP']/max(old['TP'],1);ratio=stat['FP']/max(old['FP'],1)
            stat.update(spec=review_spec['name'],start=start,retention=keep,FP_ratio=ratio,
                objective=ratio+20*max(0,.98-keep))
            results.append(stat);log(f'DEV revisão adicional {review_spec["name"]} {start}: TP={stat["TP"]}, FP={stat["FP"]}',flush=True)
    table=pd.DataFrame(results);summary=table.groupby('spec').objective.agg(['mean','std'])
    summary['selection_score']=summary['mean']+.25*summary['std'].fillna(0)
    chosen=str(summary.selection_score.idxmin())
    joblib.dump(dict(oof=records,folds=nested_folds,records=table,summary=summary,chosen=chosen),work/'double_selection.joblib')
    (work/'double_frozen.json').write_text(json.dumps({'first_context_spec':spec['name'],'reviewer_spec':chosen},indent=2),encoding='utf-8')
    return table,summary,chosen
