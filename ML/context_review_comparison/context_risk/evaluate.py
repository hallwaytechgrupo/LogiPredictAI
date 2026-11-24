"""Abre os resultados finais após congelar as escolhas na validação."""
from pathlib import Path
import json,gc
import joblib,numpy as np,pandas as pd
from logipredict_final.experiment import split_at,metrics
from .runtime import ContextPipeline,DoubleReviewPipeline,meta_frame,reference_score
from .study import SPECS,REFS,RETENTIONS,MAIN_RETENTION,fit_meta,pool_for,operate
from .double_review import nested_pool,add_context_score

def row_metrics(name,reference,variant,rows,p,cut,base_p=None,base_cut=None):
    row=metrics(rows.is_late,p,cut)
    overdue=rows.already_overdue.to_numpy();decision=p>=cut;y=rows.is_late.to_numpy()
    row.update(name=name,reference=reference,variant=variant,threshold=float(cut),
        known_overdue_TP=int((decision&(y==1)&overdue).sum()),
        anticipated_TP=int((decision&(y==1)&~overdue).sum()))
    if base_p is not None:
        old=base_p>=base_cut
        row.update(removed_FP=int((old&~decision&(y==0)).sum()),lost_TP=int((old&~decision&(y==1)).sum()),
            recovered_TP=int((~old&decision&(y==1)).sum()),added_FP=int((~old&decision&(y==0)).sum()))
    return row

def evaluate_final(data,context,history,work,log=print):
    work=Path(work);selection=joblib.load(work/'selection.joblib');oof=joblib.load(work/'oof.joblib')['records']
    start=data.dispatched_at.iloc[int(len(data)*.8)]
    _,cal,_,_=split_at(data,start,data.dispatched_at.max()+pd.Timedelta(seconds=1),start)
    future=data.loc[data.dispatched_at.ge(start)]
    static_context=history.query(future,cutoff=start)
    results=[];controls=[];retention_rows=[];models={};scores={};frozen={}
    for name in REFS:
        bundle=joblib.load(work.parent/'referencias'/name/'model.joblib')
        reference=bundle['pipeline'];base_cut=bundle['metadata']['threshold']
        base_p=reference_score(reference,future);cal_p=reference_score(reference,cal)
        results.append(row_metrics(name,name,'referencia',future,base_p,base_cut))
        for mode in ['rescore','filter']:
            chosen=selection['chosen'][(name,mode)];spec=next(s for s in SPECS if s['name']==chosen)
            for use_context in [True,False]:
                x,y=pool_for(data,context,oof,name,start,mode,use_context)
                reviewer=fit_meta(spec,x,y)
                xc=meta_frame(cal,cal_p,base_cut,context.loc[cal.index] if use_context else None)
                xf=meta_frame(future,base_p,base_cut,context.loc[future.index] if use_context else None)
                cp=reviewer.predict_proba(xc)[:,1];p_raw=reviewer.predict_proba(xf)[:,1]
                cut=operate(cal.is_late,cp,cal_p,base_cut,mode)
                p=p_raw.copy()
                overdue=future.already_overdue.to_numpy()
                if mode=='filter':p=np.where(base_p>=base_cut,p,0.);p=np.where(overdue&(base_p>=base_cut),1.,p)
                else:p=np.where(overdue,1.,p)
                label=f'{name}_{mode}'+('' if use_context else '_sem_contexto')
                row=row_metrics(label,name,mode,future,p,cut,base_p,base_cut)
                row.update(spec=chosen,context=use_context)
                (results if use_context else controls).append(row)
                pipeline=ContextPipeline(reference,base_cut,reviewer,cut,history,use_context,mode=='filter')
                models[label]=pipeline;scores[label]=p
                log(f'FINAL {label}: TP={row["TP"]}, FP={row["FP"]}, FN={row["FN"]}',flush=True)
                if use_context:
                    xs=meta_frame(future,base_p,base_cut,static_context)
                    ps=reviewer.predict_proba(xs)[:,1]
                    if mode=='filter':ps=np.where(base_p>=base_cut,ps,0.);ps=np.where(overdue&(base_p>=base_cut),1.,ps)
                    else:ps=np.where(overdue,1.,ps)
                    control=row_metrics(label+'_historico_congelado',name,mode,future,ps,cut,base_p,base_cut)
                    control['context']='frozen_at_training';controls.append(control)
                    if mode=='filter':
                        for retain in RETENTIONS:
                            tc=operate(cal.is_late,cp,cal_p,base_cut,mode,retain)
                            stat=row_metrics(label,name,mode,future,p,tc,base_p,base_cut)
                            stat['calibration_retention']=retain;retention_rows.append(stat)
                    if name=='modelo_614' and mode=='rescore':
                        frozen=dict(pipeline=pipeline,cal_score=cp,future_score=p,cal_base_score=cal_p,
                            future_base_score=base_p,base_cut=base_cut)
    # A revisão adicional recebe previsões fora do ajuste do modelo enriquecido.
    nested=joblib.load(work/'double_selection.joblib')
    spec=next(s for s in SPECS if s['name']==nested['chosen'])
    x,y=nested_pool(data,context,nested['oof'],start);reviewer=fit_meta(spec,x,y)
    xc=add_context_score(meta_frame(cal,frozen['cal_base_score'],frozen['base_cut'],context.loc[cal.index]),frozen['cal_score'],frozen['pipeline'].threshold)
    xf=add_context_score(meta_frame(future,frozen['future_base_score'],frozen['base_cut'],context.loc[future.index]),frozen['future_score'],frozen['pipeline'].threshold)
    cp=reviewer.predict_proba(xc)[:,1];p=reviewer.predict_proba(xf)[:,1]
    gate=frozen['future_score']>=frozen['pipeline'].threshold
    p=np.where(gate,p,0.);p=np.where(future.already_overdue.to_numpy()&gate,1.,p)
    cut=operate(cal.is_late,cp,frozen['cal_score'],frozen['pipeline'].threshold,'filter')
    label='modelo_614_contexto_mais_revisao_adicional'
    pipeline=DoubleReviewPipeline(frozen['pipeline'],reviewer,cut)
    stat=row_metrics(label,'modelo_614','double_review',future,p,cut,frozen['future_score'],frozen['pipeline'].threshold)
    stat.update(spec=spec['name'],context=True);results.append(stat);models[label]=pipeline;scores[label]=p
    for retain in RETENTIONS:
        tc=operate(cal.is_late,cp,frozen['cal_score'],frozen['pipeline'].threshold,'filter',retain)
        stat=row_metrics(label,'modelo_614','double_review',future,p,tc,frozen['future_score'],frozen['pipeline'].threshold)
        stat['calibration_retention']=retain;retention_rows.append(stat)
    log(f'FINAL {label}: TP={results[-1]["TP"]}, FP={results[-1]["FP"]}, FN={results[-1]["FN"]}',flush=True)
    output=dict(results=pd.DataFrame(results),controls=pd.DataFrame(controls),retentions=pd.DataFrame(retention_rows),
        models=models,scores=scores,test_index=future.index.to_numpy(),test_start=start)
    joblib.dump(output,work/'final.joblib',compress=3)
    output['results'].to_csv(work/'final_results.csv',index=False)
    output['controls'].to_csv(work/'controls.csv',index=False)
    output['retentions'].to_csv(work/'retention_profiles.csv',index=False)
    return output

def export_models(work):
    work=Path(work);r=joblib.load(work/'final.joblib');bundle=joblib.load(work/'data_context.joblib')
    destination=work.parent/'novos_modelos';destination.mkdir(exist_ok=True)
    for label,pipeline in r['models'].items():
        if label.endswith('_sem_contexto'):continue
        directory=destination/label;directory.mkdir(exist_ok=True)
        row=r['results'].loc[r['results'].name.eq(label)].iloc[0].to_dict()
        metadata=dict(version=label,source='olist',synthetic=False,threshold=float(pipeline.threshold),
            trained_asof=str(r['test_start']),metrics=row,activated=False,
            probability_calibrated=False,
            input_contract='raw Shipment + optional seller_id, origin_prefix5, destination_prefix5',
            history_protocol='Prequential: only completed deliveries strictly before each prediction; no test labels used to adjust weights or thresholds.',
            history_population='Olist eligible eventually-delivered cohort; excludes open/cancelled orders from evaluation.',
            raw_manifest=bundle['manifest'],evaluation='Exploratory retrospective benchmark; final period reused in earlier research.',
            integration='Enriched service required; existing main frame of 13 attributes cannot supply seller/ZIP history.',
            score_meaning='Conditional alert score for filter variants; do not interpret as calibrated population probability.')
        joblib.dump({'pipeline':pipeline,'metadata':metadata},directory/'model.joblib',compress=3)
        (directory/'metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    from logipredict_final.data import shipment_row
    future=bundle['data'].loc[r['test_index']]
    pipeline=r['models']['modelo_614_rescore'];scores=r['scores']['modelo_614_rescore']
    candidates=np.flatnonzero((scores>=pipeline.threshold)&future.is_late.eq(1).to_numpy())
    row=future.iloc[int(candidates[0]) if len(candidates) else 0]
    example=shipment_row(row)
    example.update({c:str(row[c]) for c in ['seller_id','origin_prefix5','destination_prefix5']})
    (work.parent/'exemplo_enriquecido.json').write_text(json.dumps(example,ensure_ascii=False,indent=2),encoding='utf-8')
    return destination
