"""Avaliação final sem balancear, limpar ou excluir pedidos reais do teste."""
from pathlib import Path
import copy,json,hashlib,platform
import importlib.metadata
import joblib,numpy as np,pandas as pd
from logipredict_final.experiment import split_at,metrics
from context_risk.study import pool_for,operate
from context_risk.runtime import meta_frame,reference_score
from .study import BASES,train_reviewer
from .resampling import METHODS

def stats(rows,p,cut,old_p=None,old_cut=None):
    out=metrics(rows.is_late,p,cut)
    decision=p>=cut;y=rows.is_late.to_numpy();overdue=rows.already_overdue.to_numpy()
    out.update(accuracy=(out['TP']+out['TN'])/len(rows),
        anticipated_TP=int((decision&(y==1)&~overdue).sum()),
        known_overdue_TP=int((decision&(y==1)&overdue).sum()))
    if old_p is not None:
        old=old_p>=old_cut
        out.update(removed_FP=int((old&~decision&(y==0)).sum()),lost_TP=int((old&~decision&(y==1)).sum()),
            recovered_TP=int((~old&decision&(y==1)).sum()),added_FP=int((~old&decision&(y==0)).sum()))
    return out

def evaluate_final(bundle,oof,work,log=print):
    work=Path(work);root=work.parent;data,context=bundle['data'],bundle['context']
    selection=joblib.load(work/'selection.joblib')['frozen']
    start=data.dispatched_at.iloc[int(len(data)*.8)]
    _,cal,_,_=split_at(data,start,data.dispatched_at.max()+pd.Timedelta(seconds=1),start)
    test=data.loc[data.dispatched_at.ge(start)]
    rows=[];models={};scores={};audits={};reference_scores={}
    for base,definition in BASES.items():
        frozen=joblib.load(root/'preservados'/base/'model.joblib')
        template=frozen['pipeline'];oldp=template.predict_proba(test)[:,1]
        reference_scores[base]=oldp
        base_stats=stats(test,oldp,template.threshold)
        assert all(base_stats[k]==frozen['metadata']['metrics'][k] for k in ['TP','FP','FN'])
        base_stats.update(base=base,method='preservado',family='referencia',threshold=template.threshold)
        rows.append(base_stats)
        base_cal=reference_score(template.reference,cal);base_test=reference_score(template.reference,test)
        xc=meta_frame(cal,base_cal,template.reference_threshold,context.loc[cal.index])
        xt=meta_frame(test,base_test,template.reference_threshold,context.loc[test.index])
        x,y=pool_for(data,context,oof['records'],definition['reference'],start,'filter',True)
        for name in selection['selected'][base]:
            method=next(m for m in METHODS if m['name']==name)
            reviewer,audit=train_reviewer(x,y,method,work,f'FINAL_{base}_{name}')
            audit.update(max_training_dispatch=str(data.loc[x.index].dispatched_at.max()),
                         max_training_label_available=str(data.loc[x.index].label_known_at.max()),
                         fitted_asof=str(start),real_calibration_rows=len(cal),real_test_rows=len(test))
            (work/'audits'/f'FINAL_{base}_{name}.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
            cp=reviewer.predict_proba(xc)[:,1];p=reviewer.predict_proba(xt)[:,1]
            cut=operate(cal.is_late,cp,base_cal,template.reference_threshold,'filter',definition['retention'])
            gate=base_test>=template.reference_threshold
            p=np.where(gate,p,0.)
            p=np.where(test.already_overdue.to_numpy()&gate,1.,p)
            row=stats(test,p,cut,oldp,template.threshold)
            row.update(base=base,method=name,family=method['family'],threshold=cut,
                synthetic_rows=audit['synthetic_rows'],duplicated_rows=audit['duplicated_rows'],removed_rows=audit['removed_rows'])
            if name=='controle':
                assert (row['TP'],row['FP'],row['FN'])==(base_stats['TP'],base_stats['FP'],base_stats['FN']),row
                np.testing.assert_allclose(p,oldp,rtol=1e-8,atol=1e-10)
            pipeline=copy.copy(template);pipeline.reviewer=reviewer;pipeline.threshold=cut
            label=base+'_'+name;models[label]=pipeline;scores[label]=p;audits[label]=audit;rows.append(row)
            log(f'FINAL {label}: TP={row["TP"]}, FP={row["FP"]}, FN={row["FN"]}, '
                f'artificiais={audit["synthetic_rows"]}, removidos={audit["removed_rows"]}',flush=True)
    result=dict(table=pd.DataFrame(rows),models=models,scores=scores,audits=audits,
                reference_scores=reference_scores,test_index=test.index.to_numpy(),start=start,selection=selection)
    result['table'].to_csv(work/'final_results.csv',index=False)
    joblib.dump(result,work/'evaluation.joblib',compress=3)
    return result

def export_models(work):
    work=Path(work);root=work.parent;r=joblib.load(work/'evaluation.joblib');bundle=joblib.load(work/'data.joblib')
    directory=root/'modelos_novos';directory.mkdir(exist_ok=True)
    import importlib.metadata
    versions={name:importlib.metadata.version(name) for name in ['catboost','scikit-learn','imbalanced-learn','sklearn-compat','numpy','pandas','joblib']}
    source_hash=hashlib.sha256(b''.join(p.read_bytes() for p in sorted((root/'sampling_risk').glob('*.py')))).hexdigest()
    for label,pipeline in r['models'].items():
        row=r['table'].loc[(r['table'].base+'_'+r['table'].method).eq(label)].iloc[0]
        audit=r['audits'][label];synthetic=bool(audit['synthetic_rows'])
        metadata=dict(version=label,source='olist',synthetic=synthetic,threshold=float(pipeline.threshold),
            metrics=row.to_dict(),study_date='2026-11-22',trained_asof=str(r['start']),activated=False,
            reviewer_only_resampling=True,training_augmentation=synthetic,sampling_audit=audit,
            probability_calibrated=False,versions=versions,python_version=platform.python_version(),
            source_sha256=source_hash,real_dataset_manifest=bundle['manifest'],
            input_contract='raw Shipment + seller_id, origin_prefix5, destination_prefix5',
            test_protocol='19258 real orders, no test resampling/deletion; original temporal cut; historical context uses only observed past deliveries.',
            limitations=['Retrospective historical test period reused in earlier studies; independent confirmation still required.',
                'Synthetic vectors are assumptions in training feature space, not real shipments or observed delay outcomes.',
                'Only the reviewer changed. The original first detector caps the number of recoverable delays.',
                'Scores are conditional on reference alerts, not calibrated population probabilities.'])
        target=directory/label;target.mkdir(exist_ok=True)
        joblib.dump({'pipeline':pipeline,'metadata':metadata},target/'model.joblib',compress=3)
        (target/'metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    from logipredict_final.data import shipment_row
    row=bundle['data'].loc[r['test_index'][0]];example=shipment_row(row)
    example.update({c:str(row[c]) for c in ['seller_id','origin_prefix5','destination_prefix5']})
    (root/'exemplo_real.json').write_text(json.dumps(example,ensure_ascii=False,indent=2),encoding='utf-8')
    return directory
