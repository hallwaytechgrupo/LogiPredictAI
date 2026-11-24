"""Audita causalidade do contexto, referências preservadas e contratos de inferência."""
from pathlib import Path
import json,hashlib,time
import joblib,numpy as np,pandas as pd
from fastapi.testclient import TestClient
from logipredict_final.data import shipment_row
from logipredict_final.experiment import metrics
from .history import HistoryStore
from .study import pool_for,REFS
from .runtime import reference_score,DoubleReviewPipeline
from .service import create_app

def verify(work):
    work=Path(work);b=joblib.load(work/'data_context.joblib');data=b['data'];store=b['history'];context=b['context']
    r=joblib.load(work/'final.joblib');future=data.loc[r['test_index']];checks={}
    for name,files in json.loads((work.parent/'referencias/sha256.json').read_text(encoding='utf-8')).items():
        assert all(hashlib.sha256((work.parent/'referencias'/name/f).read_bytes()).hexdigest()==h for f,h in files.items())
    checks['three_frozen_reference_hashes']=True
    old=json.loads((work/'previous_files_sha256.json').read_text(encoding='utf-8'))
    repo=work.parent.parent.parent
    targets=[(Path(f) if Path(f).is_absolute() else repo/Path(f),h) for f,h in old.items()]
    if all(p.exists() for p,h in targets):
        assert all(hashlib.sha256(p.read_bytes()).hexdigest()==h for p,h in targets)
        checks['previous_study_files_preserved']=True
    else:checks['previous_study_files_preserved']='Originais externos ausentes; manifesto das três referências verificado.'
    # Consulta individual otimizada precisa coincidir com o cálculo de todos os pedidos.
    sample=data.sample(8,random_state=42)
    single=store.query(sample)
    for c in context.select_dtypes('number'):
        np.testing.assert_allclose(single[c],context.loc[sample.index,c],equal_nan=True,rtol=1e-10,atol=1e-10)
    checks['individual_and_batch_history_match']=True
    for _,row in sample.iloc[:4].iterrows():
        query=pd.DataFrame([row]);qtime=row.dispatched_at
        ev=store.events;past=ev.loc[ev.delivered_at<qtime]
        output=store.query(query)
        assert output.h_global_count.iloc[0]==len(past)
        seller=past.loc[past.seller_id.eq(row.seller_id)]
        assert output.h_seller_count.iloc[0]==len(seller)
        if len(seller):np.testing.assert_allclose(output.h_seller_duration_mean.iloc[0],seller.duration.mean())
        changed=ev.copy();mask=changed.delivered_at.ge(qtime)
        changed.loc[mask,'delivered_at']+=pd.Timedelta(days=3000)
        changed.loc[mask,'duration']+=3000;changed.loc[mask,'is_late']=1-changed.loc[mask,'is_late']
        altered=HistoryStore(changed).query(query)
        pd.testing.assert_frame_equal(output,altered,check_exact=False,rtol=1e-10,atol=1e-10)
    checks['future_events_do_not_change_past_features']=True
    # Um evento exatamente na hora da previsão ainda NÃO pode ser usado.
    event=store.events.iloc[5000];query=sample.iloc[:1].copy();query['dispatched_at']=event.delivered_at
    output=store.query(query)
    assert output.h_global_count.iloc[0]==int(store.events.delivered_at.lt(event.delivered_at).sum())
    checks['exact_time_events_excluded']=True
    oof=joblib.load(work/'oof.joblib')['records'];altered=data.copy();mask=altered.dispatched_at.ge(r['test_start'])
    altered.loc[mask,'is_late']=1-altered.loc[mask,'is_late']
    for ref in REFS:
        for mode in ['rescore','filter']:
            x,y=pool_for(data,context,oof,ref,r['test_start'],mode,True)
            xx,yy=pool_for(altered,context,oof,ref,r['test_start'],mode,True)
            pd.testing.assert_frame_equal(x,xx);np.testing.assert_array_equal(y,yy)
    checks['training_pools_ignore_final_targets']=True
    for label,model in r['models'].items():
        if label.endswith('_sem_contexto'):continue
        rows=future.sample(12,random_state=42)
        p=model.predict_proba(rows)[:,1];idx=future.index.get_indexer(rows.index)
        np.testing.assert_allclose(p,r['scores'][label][idx],rtol=1e-8,atol=1e-10)
        if isinstance(model,DoubleReviewPipeline):
            assert ((p>=model.threshold)<=(model.first_stage.predict(rows)==1)).all()
        elif model.filter_only:
            assert ((p>=model.threshold)<=(reference_score(model.reference,rows)>=model.reference_threshold)).all()
    checks['vetoes_only_remove_alerts']=True
    checks['exported_models_same_scores']=True
    label='modelo_614_contexto_mais_revisao_adicional';directory=work.parent/'novos_modelos'/label
    exported=joblib.load(directory/'model.joblib');row=future.iloc[0];payload=shipment_row(row)
    payload.update(seller_id=row.seller_id,origin_prefix5=row.origin_prefix5,destination_prefix5=row.destination_prefix5)
    with TestClient(create_app(directory)) as client:
        began=time.perf_counter();response=client.post('/predict',json=payload);latency=(time.perf_counter()-began)*1000
        assert response.status_code==200,response.text
        full=response.json();assert full['decision_source']=='context_model'
        np.testing.assert_allclose(full['delay_probability'],exported['pipeline'].predict_proba(pd.DataFrame([row]))[0,1])
        old_payload=shipment_row(row);response=client.post('/predict',json=old_payload)
        assert response.status_code==200
        assert response.json()['decision_source']=='reference_missing_context'
        first=exported['pipeline'].first_stage
        np.testing.assert_allclose(response.json()['delay_probability'],reference_score(first.reference,pd.DataFrame([row]))[0])
        assert response.json()['threshold']==first.reference_threshold
        assert client.post('/predict',json={**payload,'is_late':1}).status_code==422
        assert client.post('/predict',json={**payload,'origin_prefix5':'01001000'}).status_code==422
        assert client.post('/predict',json={**payload,'seller_state':'XX'}).status_code==422
    checks['http_contract_and_reference_fallback']={'status':'passed','first_request_ms':round(latency,1),'response':full}
    (work/'verification.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
    return checks
