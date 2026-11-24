"""Audita preservação, treino isolado, vetores artificiais e contrato de inferência."""
from pathlib import Path
import json,hashlib
import joblib,numpy as np,pandas as pd
from fastapi.testclient import TestClient
from context_risk.study import pool_for
from context_risk.runtime import reference_score
from .resampling import METHODS,resample
from .study import BASES
from .service import create_app

def verify(work):
    work=Path(work);root=work.parent;b=joblib.load(work/'data.joblib');r=joblib.load(work/'evaluation.joblib')
    checks={};data=b['data'];test=data.loc[r['test_index']]
    assert len(test)==19258 and int(test.is_late.sum())==704 and test.order_id.is_unique
    checks['real_holdout_19258_orders_704_delays']=True
    for base,files in json.loads((root/'preservados/sha256.json').read_text(encoding='utf-8')).items():
        assert all(hashlib.sha256((root/'preservados'/base/f).read_bytes()).hexdigest()==h for f,h in files.items())
    checks['two_preserved_model_hashes']=True
    previous_file=work/'previous_sha256.json'
    if not previous_file.exists():previous_file=root/'reports/previous_sha256.json'
    previous=json.loads(previous_file.read_text(encoding='utf-8')) if previous_file.exists() else {}
    if previous and all(Path(f).exists() for f in previous):
        assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in previous.items())
        checks['previous_models_and_notebooks_unchanged']=True
    else:checks['previous_models_and_notebooks_unchanged']='Originais externos indisponíveis; cópias preservadas verificadas.'
    oof=joblib.load(root/'training_inputs/oof.joblib')
    x,y=pool_for(data,b['context'],oof['records'],'modelo_564','2017-12-01','filter',True)
    before=x.copy(deep=True)
    for method in METHODS:
        sampled,labels,audit=resample(x,y,method)
        again,labels2,audit2=resample(x,y,method)
        pd.testing.assert_frame_equal(sampled,again);np.testing.assert_array_equal(labels,labels2)
        pd.testing.assert_frame_equal(x,before)
        if method['name'] in ['reduzir_pontuais_50','manter_pontuais_dificeis_50','tomek_pontuais']:
            assert int((labels==1).sum())==int((y==1).sum())
        if method['name'] in ['smotenc_atrasos_2x','smotenc_pontuais_125']:
            pd.testing.assert_frame_equal(sampled.iloc[:len(x)].reset_index(drop=True),x.reset_index(drop=True),check_dtype=False)
            extra=sampled.iloc[len(x):]
            assert extra.sellers_count.le(extra.items_count).all()
            assert extra.items_count.ge(1).all() and extra.remaining_days.ge(0).all()
            assert extra.purchase_month.between(1,12).all() and extra.dispatch_weekday.between(0,6).all()
            assert extra.route_state.eq(extra.seller_state+'>'+extra.customer_state).all()
            for c in extra:
                if c.startswith('h_') and '_late_rate' in c:assert extra[c].between(0,1).all()
            assert not np.isinf(extra.select_dtypes('number').to_numpy()).any()
    checks['sampling_reproducible_and_input_unchanged']=True
    checks['deletion_preserves_all_real_training_delays']=True
    checks['synthetic_bounds_and_deterministic_relations']=True
    # Trocar os rótulos finais não pode mudar nenhuma linha do ajuste.
    changed=data.copy();mask=changed.dispatched_at.ge(r['start']);changed.loc[mask,'is_late']=1-changed.loc[mask,'is_late']
    for base,definition in BASES.items():
        xx,yy=pool_for(data,b['context'],oof['records'],definition['reference'],r['start'],'filter',True)
        zz,ww=pool_for(changed,b['context'],oof['records'],definition['reference'],r['start'],'filter',True)
        pd.testing.assert_frame_equal(xx,zz);np.testing.assert_array_equal(yy,ww)
        assert data.loc[xx.index].label_known_at.max()<r['start']
        assert set(xx.index).isdisjoint(test.index)
    checks['resampling_sources_exclude_calibration_and_holdout']=True
    for label,pipeline in r['models'].items():
        rows=test.sample(12,random_state=42)
        saved=joblib.load(root/'modelos_novos'/label/'model.joblib')
        np.testing.assert_allclose(saved['pipeline'].predict_proba(rows),pipeline.predict_proba(rows),atol=0,rtol=0)
        idx=test.index.get_indexer(rows.index)
        p=pipeline.predict_proba(rows)[:,1]
        np.testing.assert_allclose(p,r['scores'][label][idx],rtol=1e-8,atol=1e-10)
        pd.testing.assert_frame_equal(pipeline.history.events,b['history'].events)
        gate=reference_score(pipeline.reference,rows)>=pipeline.reference_threshold
        assert ((p>=pipeline.threshold)<=gate).all()
        assert saved['metadata']['synthetic']==bool(r['audits'][label]['synthetic_rows'])
    checks['no_synthetic_events_added_to_history']=True
    checks['serialization_and_pipeline_scores_match']=True
    checks['first_detector_gates_preserved']=True
    checks['synthetic_training_flag_matches_audit']=True
    synthetic_label=next(k for k,v in r['audits'].items() if v['synthetic_rows']>0)
    path=root/'modelos_novos'/synthetic_label
    payload=json.loads((root/'exemplo_real.json').read_text(encoding='utf-8'))
    with TestClient(create_app(path)) as client:
        assert client.get('/health').json()['synthetic'] is True
        response=client.post('/predict',json=payload)
        assert response.status_code==200,response.text
        out=response.json();assert out['synthetic'] is True and out['training_augmentation_used'] is True
        assert out['predicted_late']==(out['delay_probability']>=out['threshold'])
        no_context={k:v for k,v in payload.items() if k not in ['seller_id','origin_prefix5','destination_prefix5']}
        fallback=client.post('/predict',json=no_context).json()
        assert fallback['synthetic'] is False and fallback['decision_source']=='reference_missing_context'
        assert client.post('/predict',json={**payload,'is_late':1}).status_code==422
        assert client.post('/predict',json={**payload,'items_count':0}).status_code==422
    checks['http_flags_fallback_and_validation']='passed'
    (work/'verification.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
    return checks
