"""Segunda rodada declarada: regressão de duração, RF com cruzamentos e blends.

A comparação continua retrospectiva. A seleção usa somente os mesmos quatro
meses de desenvolvimento, embora o período final já tenha sido examinado.
"""
from pathlib import Path
import gc,json,time
import joblib,numpy as np,pandas as pd
from catboost import CatBoostRegressor
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from .features import feature_frame,enrich,encoder
from .runtime import BaseModel,BlendModel,logit
from .experiment import (SEED,THREADS,PRIMARY_TARGET,DEV_STARTS,BASE_SPECS,split_at,
    fit_base,calibrated_base,candidate_record,spec_by_name)

EXTRA_SPECS=[dict(name=f'duration_{loss}',kind='duration',loss=loss) for loss in ['RMSE','Q50','Q80','Q90']]+[
    dict(name='rf_derived_leaf10',kind='rf_derived',leaf=10,balanced=True),
    dict(name='rf_derived_leaf30',kind='rf_derived',leaf=30,balanced=True),
    dict(name='rf_derived_unweighted',kind='rf_derived',leaf=10,balanced=False)]
BLEND_PAIRS=[('rf_main','aft_extreme_0.5_3'),('cb150','aft_extreme_0.5_3'),('rf_main','cb150')]
BLEND_SPECS=[dict(name=f'blend_{a}_{b}_{weight}',kind='blend',a=a,b=b,weight=weight)
             for a,b in BLEND_PAIRS for weight in [.25,.5,.75]]
MATURITY_SPECS=[dict(name=f'mature_{base}_{mode}',kind='mature',base=base,mode=mode)
               for base in ['rf_main','cb150'] for mode in ['gap35','gap60','cal60']]

def mature_split(data,start,end,selection_cut,mode):
    train,cal,_,future=split_at(data,start,end,selection_cut)
    if mode=='cal60':
        # Uma calibração mais antiga tem mais entregas já concluídas em E.
        start=pd.Timestamp(start)
        before=data.dispatched_at.lt(start-pd.Timedelta(days=60))&~data.already_overdue
        train=data.loc[before].copy()
        cal=data.loc[data.dispatched_at.between(start-pd.Timedelta(days=60),start-pd.Timedelta(days=35),inclusive='left')
            &~data.already_overdue&data.label_known_at.lt(start)].copy()
    else:
        gap=int(mode[3:])
        train=train.loc[train.dispatched_at.lt(pd.Timestamp(start)-pd.Timedelta(days=gap))]
    assert set(train.order_id).isdisjoint(cal.order_id)
    return train,cal,future

def fit_extra(spec,train,start):
    mask=train.delivered_at.lt(pd.Timestamp(start)) if spec['kind']=='duration' else train.label_known_at.lt(pd.Timestamp(start))
    fit=train.loc[mask];z=enrich(feature_frame(fit));prep=encoder(z);matrix=prep.fit_transform(z)
    if spec['kind']=='duration':
        loss='RMSE' if spec['loss']=='RMSE' else 'Quantile:alpha='+str(int(spec['loss'][1:])/100)
        model=CatBoostRegressor(iterations=400,depth=6,learning_rate=.05,l2_leaf_reg=15.,
            loss_function=loss,thread_count=THREADS,random_seed=SEED,allow_writing_files=False,verbose=False)
        model.fit(matrix,fit.event_duration.to_numpy()-1)
        kind='duration'
    else:
        model=RandomForestClassifier(n_estimators=300,max_depth=16,min_samples_leaf=spec['leaf'],
            class_weight='balanced_subsample' if spec['balanced'] else None,n_jobs=THREADS,random_state=SEED)
        model.fit(matrix,fit.is_late)
        kind='rf'
    return BaseModel(prep,model,kind,True)

def make_blend(spec,bases,cal):
    models=[bases[spec['a']],bases[spec['b']]];transforms=[]
    for model in models:
        score=model.raw_score(feature_frame(cal))
        transform=LogisticRegression(C=1.,random_state=SEED).fit(logit(score).reshape(-1,1),cal.is_late)
        assert transform.coef_[0,0]>0
        transforms.append(transform)
    return BlendModel(models,transforms,[spec['weight'],1-spec['weight']])

def run_refinements(data,work,log=print):
    work=Path(work);selection=joblib.load(work/'selection.joblib')
    if (work/'initial_selection.joblib').exists():
        selection=joblib.load(work/'initial_selection.joblib')
    else:
        joblib.dump(selection,work/'initial_selection.joblib')
    # A lista é publicada antes de executar a nova busca; não contém decisões do teste.
    (work/'refinement_plan.json').write_text(json.dumps(EXTRA_SPECS+BLEND_SPECS,indent=2),encoding='utf-8')
    records=selection['records'].to_dict('records');cut=selection['test_start']
    for start in DEV_STARTS:
        train,cal,_,future=split_at(data,start,pd.Timestamp(start)+pd.DateOffset(months=1),cut)
        for spec in EXTRA_SPECS:
            began=time.perf_counter();base=fit_extra(spec,train,start)
            pipeline=calibrated_base(base,cal,PRIMARY_TARGET)
            row=candidate_record(spec['name'],spec['kind'],start,future,pipeline);records.append(row)
            log(f'REFINO {spec["name"]} {start}: recall={row["recall"]:.3f}, FP={row["FP"]}, {time.perf_counter()-began:.1f}s',flush=True)
            del base,pipeline;gc.collect()
        bases={name:fit_base(spec_by_name(name)[0],train,start) for name in ['rf_main','cb150','aft_extreme_0.5_3']}
        for spec in BLEND_SPECS:
            base=make_blend(spec,bases,cal);pipeline=calibrated_base(base,cal,PRIMARY_TARGET)
            row=candidate_record(spec['name'],'blend',start,future,pipeline);records.append(row)
            log(f'REFINO {spec["name"]} {start}: recall={row["recall"]:.3f}, FP={row["FP"]}',flush=True)
        del bases,base,pipeline;gc.collect()
        joblib.dump(records,work/'refinement_records.joblib')
    table=pd.DataFrame(records)
    summary=table.groupby(['name','family']).agg(objective=('objective','mean'),variation=('objective','std'),
        recall=('recall','mean'),FPR=('FPR','mean'),AP=('AP','mean'))
    summary['selection_score']=summary.objective+.25*summary.variation.fillna(0)
    summary=summary.sort_values('selection_score');summary.to_csv(work/'development_summary.csv')
    selection.update(records=table,summary=summary)
    joblib.dump(selection,work/'selection.joblib')
    return table,summary,selection['oof']

def fit_refined(name,data,start,end,target):
    train,cal,_,future=split_at(data,start,end,pd.Timestamp(start))
    spec=next(s for s in EXTRA_SPECS+BLEND_SPECS+MATURITY_SPECS if s['name']==name)
    if spec['kind']=='mature':
        train,cal,future=mature_split(data,start,end,pd.Timestamp(start),spec['mode'])
        base=fit_base(spec_by_name(spec['base'])[0],train,start)
    elif spec['kind']=='blend':
        bases={k:fit_base(spec_by_name(k)[0],train,start) for k in [spec['a'],spec['b']]}
        base=make_blend(spec,bases,cal)
    else:
        base=fit_extra(spec,train,start)
    return calibrated_base(base,cal,target),base,None,cal,future


def run_maturity(data,work,log=print):
    """Testa o viés de incluir só os desfechos rápidos dos despachos recentes."""
    work=Path(work);selection=joblib.load(work/'selection.joblib');cut=selection['test_start']
    records=selection['records'].loc[~selection['records'].family.eq('mature')].to_dict('records')
    (work/'maturity_plan.json').write_text(json.dumps(MATURITY_SPECS,indent=2),encoding='utf-8')
    for spec in MATURITY_SPECS:
        for start in DEV_STARTS:
            train,cal,future=mature_split(data,start,pd.Timestamp(start)+pd.DateOffset(months=1),cut,spec['mode'])
            base=fit_base(spec_by_name(spec['base'])[0],train,start)
            pipeline=calibrated_base(base,cal,PRIMARY_TARGET)
            row=candidate_record(spec['name'],'mature',start,future,pipeline);records.append(row)
            log(f'MATURAÇÃO {spec["name"]} {start}: recall={row["recall"]:.3f}, FP={row["FP"]}',flush=True)
            del base,pipeline;gc.collect()
    table=pd.DataFrame(records)
    summary=table.groupby(['name','family']).agg(objective=('objective','mean'),variation=('objective','std'),
        recall=('recall','mean'),FPR=('FPR','mean'),AP=('AP','mean'))
    summary['selection_score']=summary.objective+.25*summary.variation.fillna(0)
    summary=summary.sort_values('selection_score');summary.to_csv(work/'development_summary.csv')
    selection.update(records=table,summary=summary);joblib.dump(selection,work/'selection.joblib')
    return table,summary,selection['oof']
