"""Ajusta revisores com amostragem e escolhe estratégias só na validação temporal."""
from pathlib import Path
import json,hashlib,time,gc
import joblib,numpy as np,pandas as pd
from logipredict_final.data import load_orders
from logipredict_final.experiment import DEV_STARTS,metrics
from context_risk.history import HistoryStore
from context_risk.study import pool_for,fit_meta,operate
from context_risk.runtime import meta_frame
from .resampling import METHODS,resample

BASES={'base_564':dict(reference='modelo_564',retention=.99),
       'base_613':dict(reference='modelo_614',retention=.95)}
SPEC=dict(name='cb350_d6',kind='cb',trees=350,depth=6)

def load_data(root):
    root=Path(root);data,manifest=load_orders()
    expected=json.loads((root/'training_inputs/data_manifest.json').read_text(encoding='utf-8'))
    assert manifest==expected,'Dados de origem mudaram; não compare coortes diferentes.'
    old=root.parent/'context_review_comparison/artifacts/data_context.joblib'
    if old.exists():
        cached=joblib.load(old);assert cached['manifest']==manifest
        assert data.order_id.tolist()==cached['data'].order_id.tolist()
        history,context=cached['history'],cached['context']
    else:
        history=HistoryStore.from_orders(data);context=history.query(data)
    return dict(data=data,context=context,history=history,manifest=manifest)

def train_reviewer(x,y,method,work=None,label=None):
    began=time.perf_counter();sampled,labels,audit=resample(x,y,method)
    model=fit_meta(SPEC,sampled,labels)
    audit['elapsed_seconds']=time.perf_counter()-began
    audit['input_index_sha256']=hashlib.sha256(np.asarray(x.index,dtype='int64').tobytes()).hexdigest()
    if work is not None and label:
        path=Path(work)/'audits';path.mkdir(exist_ok=True)
        (path/f'{label}.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
        if audit['synthetic_rows'] and not (Path(work)/'exemplo_vetores_sinteticos.csv').exists():
            # Apenas para inspecionar o formato; não são pedidos importáveis.
            selected=sampled.iloc[len(x):len(x)+12].copy()
            selected['ARTIFICIAL_TREINO']=True
            selected.to_csv(Path(work)/'exemplo_vetores_sinteticos.csv',index=False)
    return model,audit

def fold_score(data,context,fold,reviewer,retention):
    cal=data.loc[fold['cal_index']];future=data.loc[fold['future_index']]
    xc=meta_frame(cal,fold['cal_score'],fold['threshold'],context.loc[cal.index])
    xf=meta_frame(future,fold['future_score'],fold['threshold'],context.loc[future.index])
    cp=reviewer.predict_proba(xc)[:,1];p=reviewer.predict_proba(xf)[:,1]
    cut=operate(cal.is_late,cp,fold['cal_score'],fold['threshold'],'filter',retention)
    p=np.where(fold['future_score']>=fold['threshold'],p,0.)
    row=metrics(future.is_late,p,cut)
    row['threshold']=cut
    row['accuracy']=(row['TP']+row['TN'])/len(future)
    return row

def run_development(bundle,oof,work,log=print):
    data,context=bundle['data'],bundle['context'];work=Path(work)
    rows=[];controls={}
    for base,definition in BASES.items():
        for method in METHODS:
            for start in DEV_STARTS:
                x,y=pool_for(data,context,oof['records'],definition['reference'],start,'filter',True)
                source=data.loc[x.index]
                assert source.label_known_at.max()<pd.Timestamp(start)
                assert source.dispatched_at.max()<pd.Timestamp(start)-pd.Timedelta(days=35)
                model,audit=train_reviewer(x,y,method,work,f'{base}_{method["name"]}_{start}')
                row=fold_score(data,context,oof['folds'][(definition['reference'],start)],model,definition['retention'])
                if method['name']=='controle':controls[(base,start)]=row.copy()
                control=controls[(base,start)]
                keep=row['TP']/max(control['TP'],1)
                ratio=row['FP']/control['FP'] if control['FP'] else float(row['FP'])
                row.update(base=base,method=method['name'],family=method['family'],start=start,
                    retained_TP=keep,FP_ratio=ratio,objective=ratio+20*max(0,.99-keep),
                    synthetic_rows=audit['synthetic_rows'],removed_rows=audit['removed_rows'],
                    duplicated_rows=audit['duplicated_rows'],seconds=audit['elapsed_seconds'])
                rows.append(row)
                joblib.dump(rows,work/'development_records.joblib')
                log(f'DEV {base} {method["name"]} {start}: TP={row["TP"]}, FP={row["FP"]}, '
                    f'artificiais={row["synthetic_rows"]}, removidos={row["removed_rows"]}, {row["seconds"]:.1f}s',flush=True)
                del model;gc.collect()
    return summarize(rows,work)

def summarize(rows,work):
    work=Path(work)
    table=pd.DataFrame(rows)
    summary=table.groupby(['base','method','family']).agg(objective=('objective','mean'),std=('objective','std'),
        retained_TP=('retained_TP','mean'),worst_retention=('retained_TP','min'),FP_ratio=('FP_ratio','mean'))
    summary['selection_score']=summary.objective+.25*summary['std'].fillna(0)
    summary=summary.sort_values('selection_score',kind='stable')
    selected={};global_best={}
    flat=summary.reset_index()
    for base in BASES:
        current=flat.loc[flat.base.eq(base)].sort_values('selection_score',kind='stable')
        global_best[base]=str(current.iloc[0]['method'])
        names=['controle',global_best[base]]
        for family in ['sinteticos','eliminacao','duplicacao','combinacao']:
            names.append(str(current.loc[current.family.eq(family)].iloc[0]['method']))
        selected[base]=list(dict.fromkeys(names))
    summary.to_csv(work/'development_summary.csv')
    frozen=dict(selected=selected,global_best=global_best,
        criterion='mean(FP_ratio + 20*max(0,0.99-TP_retention)) + 0.25*std; comparison to unresampled control',
        primary_retention={k:v['retention'] for k,v in BASES.items()},
        status='Frozen before new holdout metrics; exploratory reused historical cohort.')
    (work/'frozen_selection.json').write_text(json.dumps(frozen,ensure_ascii=False,indent=2),encoding='utf-8')
    joblib.dump(dict(records=table,summary=summary,frozen=frozen),work/'selection.joblib')
    return table,summary,frozen
