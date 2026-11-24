"""Congela a escolha na validação; só depois abre o período de avaliação final."""
from pathlib import Path
import hashlib,json,platform,subprocess
from datetime import datetime,timezone
import joblib,numpy as np,pandas as pd
from sklearn.metrics import brier_score_loss
from .data import DATA_COMMIT,shipment_row
from .features import FEATURES,feature_frame
from .experiment import (TARGETS,PRIMARY_TARGET,fit_candidate,calibrated_base,
                        cascade_pipeline,metrics,cut_for_recall)


def evaluate_selected(data,work,log=print):
    work=Path(work)
    selection=joblib.load(work/'selection.joblib')
    summary=selection['summary'].reset_index()
    # A escolha é escrita antes de calcular qualquer métrica do período final.
    chosen=str(summary.iloc[0]['name'])
    names=[chosen,'rf_main']
    for family in ['cascade','aft']:
        names.append(str(summary.loc[summary.family.eq(family)].iloc[0]['name']))
    for family in ['duration','blend','rf_derived','mature']:
        if summary.family.eq(family).any():
            names.append(str(summary.loc[summary.family.eq(family)].iloc[0]['name']))
    names=list(dict.fromkeys(names))
    frozen={'primary':chosen,'candidates':names,'target':PRIMARY_TARGET,
            'criterion':'mean(FPR + 5*max(0,0.90-recall)) + 0.25*std over four development months',
            'test_start':str(selection['test_start']),
            'warning':'Retrospective Olist benchmark; this historical period has been examined in earlier studies.'}
    (work/'frozen_selection.json').write_text(json.dumps(frozen,indent=2),encoding='utf-8')
    start=selection['test_start'];end=data.dispatched_at.max()+pd.Timedelta(seconds=1)
    all_test=data.loc[data.dispatched_at.ge(start)].copy()
    known=int(all_test.already_overdue.sum());records=[];models={};scores={};details=[]
    for name in names:
        if name.startswith(('duration_','rf_derived_','blend_','mature_')):
            from .refinements import fit_refined
            _,base,verifier,cal,future=fit_refined(name,data,start,end,PRIMARY_TARGET)
        else:
            _,base,verifier,cal,future=fit_candidate(name,data,start,end,selection['oof'],PRIMARY_TARGET)
        for target in TARGETS:
            pipeline=(cascade_pipeline(base,verifier,cal,target) if verifier is not None
                      else calibrated_base(base,cal,target))
            p=pipeline.predict_proba(feature_frame(future))[:,1]
            row=metrics(future.is_late,p,pipeline.threshold)
            row.update(name=name,target=target,threshold=pipeline.threshold,
                       TP_total=row['TP']+known,FN_total=row['FN'],known_overdue=known,
                       recall_total=(row['TP']+known)/int(all_test.is_late.sum()),
                       brier=float(brier_score_loss(future.is_late,p)))
            records.append(row);models[(name,target)]=pipeline;scores[(name,target)]=p
            log(f'FINAL {name} alvo={target:.0%}: TP={row["TP_total"]}, FP={row["FP"]}, FN={row["FN"]}',flush=True)
            if verifier is not None:
                _,pb,pv=pipeline.components(feature_frame(future))
                gate=pb>=pipeline.detector_cut;decision=p>=pipeline.threshold;y=future.is_late.to_numpy()
                details.append(dict(name=name,target=target,detector_TP=int((gate&(y==1)).sum()),
                    detector_FP=int((gate&(y==0)).sum()),removed_false_alerts=int((gate&~decision&(y==0)).sum()),
                    lost_true_late=int((gate&~decision&(y==1)).sum())))
    table=pd.DataFrame(records)
    table.to_csv(work/'final_comparison.csv',index=False)
    pd.DataFrame(details).to_csv(work/'cascade_audit.csv',index=False)
    result=dict(table=table,models=models,scores=scores,all_test=all_test,future=future,
                frozen=frozen,details=pd.DataFrame(details),cal=cal)
    joblib.dump(result,work/'evaluation.joblib',compress=3)
    return result


def compare_shipped_model(data,work):
    """Compara também os pesos que estão de fato versionados na main."""
    work=Path(work)
    root=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
    artifact=work/'main_model.joblib'
    artifact.write_bytes(subprocess.check_output(['git','show',f'{DATA_COMMIT}:back/ml/models/olist/model.joblib'],cwd=root))
    shipped=joblib.load(artifact)
    result=joblib.load(work/'evaluation.joblib');future=result['future'];all_test=result['all_test']
    p=shipped['pipeline'].predict_proba(feature_frame(future))[:,1]
    # Para a comparação integral usa a saída original, sem aplicar a regra nova.
    all_p=shipped['pipeline'].predict_proba(feature_frame(all_test))[:,1]
    original=metrics(all_test.is_late,all_p,shipped['metadata']['threshold'])
    proactive=metrics(future.is_late,p,shipped['metadata']['threshold'])
    comparison={'version':shipped['metadata']['version'],'threshold':shipped['metadata']['threshold'],
                'original_full_test':original,'proactive':proactive,
                'note':'Pesos da main, sem retreino e sem regra adicional de prazo já vencido.'}
    # Compara ordenação à mesma quantidade de TP, somente como diagnóstico retrospectivo.
    # Estes cortes usam o teste; nunca são exportados para produção.
    diagnostics=[]
    for target in TARGETS:
        selected=result['models'][(result['frozen']['primary'],target)]
        current=result['scores'][(result['frozen']['primary'],target)]
        achieved=float(((current>=selected.threshold)&future.is_late.eq(1)).sum()/future.is_late.sum())
        cut=cut_for_recall(future.is_late,p,achieved)
        diagnostics.append(dict(target=target,matched_recall=achieved,
                                **metrics(future.is_late,p,cut)))
    comparison['oracle_matching_recall_not_deployable']=diagnostics
    (work/'main_comparison.json').write_text(json.dumps(comparison,ensure_ascii=False,indent=2),encoding='utf-8')
    return comparison


def export_selected(work,release=None):
    work=Path(work);release=Path(release) if release else work.parent/'release'
    release.mkdir(parents=True,exist_ok=True)
    result=joblib.load(work/'evaluation.joblib');data=joblib.load(work/'orders_clean.joblib')
    manifest=json.loads((work/'data_manifest.json').read_text(encoding='utf-8'))
    name=result['frozen']['primary'];pipeline=result['models'][(name,PRIMARY_TARGET)]
    row=result['table'].loc[result['table'].name.eq(name)&result['table'].target.eq(PRIMARY_TARGET)].iloc[0]
    import importlib.metadata
    versions={p:importlib.metadata.version(p) for p in ['numpy','pandas','scipy','scikit-learn','joblib','catboost','lightgbm','xgboost','fastapi','pydantic']}
    source_files=['data.py','features.py','runtime.py','experiment.py','refinements.py','evaluation.py']
    source_hash=hashlib.sha256(b''.join((Path(__file__).parent/f).read_bytes() for f in source_files)).hexdigest()
    digest=hashlib.sha256((json.dumps(manifest,sort_keys=True)+source_hash).encode()).hexdigest()
    comparison_path=work/'main_comparison.json'
    comparison=json.loads(comparison_path.read_text(encoding='utf-8')) if comparison_path.exists() else None
    matched=(next(v for v in comparison['oracle_matching_recall_not_deployable'] if v['target']==PRIMARY_TARGET)
             if comparison else None)
    metadata=dict(version=f'candidate-{name}-{digest[:10]}',source='olist',synthetic=False,
        trained_at=datetime.now(timezone.utc).isoformat(),algorithm=name,features=FEATURES,
        threshold=float(pipeline.threshold),threshold_selection=result['frozen']['criterion'],
        target='delivered_calendar_date > estimated_calendar_date',prediction_time='dispatch',
        probability_calibrated=True,calibration='sigmoid fitted on held-out past block; not a future guarantee',
        reference_date=str(result['frozen']['test_start']),seed=42,
        python_version=platform.python_version(),versions=versions,dataset=manifest,training_source_sha256=source_hash,
        promotion_status='candidate_not_activated',evaluation_status='retrospective_reused_historical_cohort',
        integration_recommendation=('retain_existing_model_no_reduction_in_FP_at_matched_recall'
            if matched and row['FP']>=matched['FP'] else 'requires_independent_validation'),
        matched_recall_reference_FP_diagnostic=matched['FP'] if matched else None,
        primary_target=PRIMARY_TARGET,final_metrics=row.to_dict(),
        known_overdue_policy='remaining_days < 0: deterministic flag; not model anticipation',
        limitations=['Olist 2016–2018; needs validation on recent operations.',
          'Only orders eventually delivered and passing quality checks; open/cancelled orders are outside this evaluation.',
          'No carrier, tracking events, weather, municipal holidays or seller identifiers in current API.',
          'Sigmoid calibration may drift; probabilities are estimates, not guarantees.',
          'Earlier studies examined the same historical final period; external validation still required.'])
    # Não reestima no teste nem em todo o histórico: exporta exatamente os pesos avaliados.
    joblib.dump({'pipeline':pipeline,'metadata':metadata},release/'model.joblib',compress=3)
    (release/'metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    history=data.loc[(data.dispatched_at<pd.Timestamp(metadata['reference_date']))&(data.label_known_at<pd.Timestamp(metadata['reference_date']))]
    states=history.groupby('customer_state').is_late.agg(['size','sum','mean']).reset_index()
    states.columns=['customer_state','orders','late_orders','late_rate']
    analytics=dict(source='olist',synthetic=False,type='historical_observed',
        period_start=str(history.dispatched_at.min()),period_end=str(history.dispatched_at.max()),states=states.to_dict('records'))
    (release/'analytics.json').write_text(json.dumps(analytics,ensure_ascii=False,indent=2),encoding='utf-8')
    example=shipment_row(result['future'].iloc[0])
    (release/'example_shipment.json').write_text(json.dumps(example,ensure_ascii=False,indent=2),encoding='utf-8')
    for target in TARGETS:
        profile=result['models'][(name,target)]
        joblib.dump({'pipeline':profile,'metadata':{**metadata,'threshold':float(profile.threshold),
            'primary_target':target,'final_metrics':result['table'].loc[result['table'].name.eq(name)&result['table'].target.eq(target)].iloc[0].to_dict()}},
            release/f'profile_{int(target*100)}.joblib',compress=3)
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in release.iterdir() if p.is_file() and p.name!='sha256.json'}
    (release/'sha256.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
    return metadata
