"""Verificações de vazamento temporal, serialização e contrato real da main."""
from pathlib import Path
import json,subprocess,importlib.util,sys,types,time
import joblib,numpy as np,pandas as pd
from fastapi.testclient import TestClient
from pydantic import ValidationError
from .features import FEATURES,feature_frame
from .data import DATA_COMMIT,shipment_row
from .contract import Shipment
from .experiment import survival_bounds,split_at,DEV_STARTS,build_pool,VERIFY_SPECS
from .service import create_app


def verify(work,release=None):
    work=Path(work);release=Path(release) if release else work.parent/'release'
    result=joblib.load(work/'evaluation.joblib');data=joblib.load(work/'orders_clean.joblib')
    model=joblib.load(release/'model.joblib');pipeline=model['pipeline']
    rows=result['future'].iloc[:100].copy();x=feature_frame(rows);checks={}
    sample=shipment_row(rows.iloc[0]);Shipment.model_validate(sample)
    # A inferência recebe o mesmo frame quando vem do JSON ou do treino.
    payload=pd.DataFrame([Shipment.model_validate(sample).model_dump()])
    np.testing.assert_allclose(feature_frame(payload).select_dtypes('number'),x.iloc[:1].select_dtypes('number'),equal_nan=True)
    checks['json_training_feature_parity']=True
    checks['contract_rejects_target']=False
    try:
        Shipment.model_validate({**sample,'is_late':1})
    except ValidationError:
        checks['contract_rejects_target']=True
    assert checks['contract_rejects_target']
    for start in DEV_STARTS+[result['frozen']['test_start']]:
        train,cal,_,future=split_at(data,start,pd.Timestamp(start)+pd.DateOffset(months=1),pd.Timestamp(result['frozen']['test_start']))
        assert set(train.order_id).isdisjoint(cal.order_id) and set(train.order_id).isdisjoint(future.order_id)
        assert (train.dispatched_at<pd.Timestamp(start)).all() and (cal.label_known_at<pd.Timestamp(start)).all()
    checks['temporal_isolation']=True
    from .refinements import mature_split
    for start in DEV_STARTS:
        for mode in ['gap35','gap60','cal60']:
            train,cal,future=mature_split(data,start,pd.Timestamp(start)+pd.DateOffset(months=1),pd.Timestamp(result['frozen']['test_start']),mode)
            assert set(train.order_id).isdisjoint(cal.order_id) and set(train.order_id).isdisjoint(future.order_id)
            assert (train.dispatched_at<pd.Timestamp(start)).all() and (cal.label_known_at<pd.Timestamp(start)).all()
    checks['mature_protocol_temporal_isolation']=True
    selection=joblib.load(work/'selection.joblib')
    changed=data.copy();future_mask=changed.dispatched_at.ge(pd.Timestamp(result['frozen']['test_start']))
    changed.loc[future_mask,'is_late']=1-changed.loc[future_mask,'is_late']
    for detector,oof in selection['oof'].items():
        original_pool=build_pool(data,oof,result['frozen']['test_start'],VERIFY_SPECS[0])
        changed_pool=build_pool(changed,oof,result['frozen']['test_start'],VERIFY_SPECS[0])
        pd.testing.assert_frame_equal(original_pool,changed_pool)
    checks['verifier_does_not_read_final_labels']=True
    # Mudar o desfecho FUTURO não pode alterar os limites de censura no passado.
    asof=pd.Timestamp(result['frozen']['test_start']);train,_,_,_=split_at(data,asof,asof+pd.Timedelta(days=1),asof)
    changed=train.copy();mask=changed.delivered_at.ge(asof)
    changed.loc[mask,'delivered_at']+=pd.Timedelta(days=200)
    changed.loc[mask,'event_duration']+=200
    a,b=survival_bounds(train,asof);c,d=survival_bounds(changed,asof)
    np.testing.assert_array_equal(a,c);np.testing.assert_array_equal(b,d)
    assert mask.any();checks['aft_does_not_read_future_delivery']=int(mask.sum())
    expected=result['models'][(result['frozen']['primary'],.9)].predict_proba(x)
    np.testing.assert_allclose(pipeline.predict_proba(x),expected,atol=0,rtol=0)
    checks['serialization_same_probabilities']=True
    overdue=x.iloc[:1].copy();overdue['remaining_days']=-1
    assert pipeline.predict(overdue)[0]==1 and pipeline.predict_proba(overdue)[0,1]==1
    checks['known_overdue_rule']=True
    for (name,target),candidate in result['models'].items():
        if candidate.verifier is None:
            continue
        p,pb,pv=candidate.components(x)
        np.testing.assert_array_equal(p>=candidate.threshold,(pb>=candidate.detector_cut)&(pv>=candidate.verifier_cut))
    checks['cascade_matches_both_gates']=True
    # Extrai a implementação versionada para um pacote temporário de teste.
    # Nenhuma alteração é feita no backend existente.
    root=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
    reference=work/'main_reference';reference.mkdir(exist_ok=True)
    for filename in ['schema.py','service.py']:
        (reference/filename).write_bytes(subprocess.check_output(['git','show',f'{DATA_COMMIT}:back/ml/logipredict/{filename}'],cwd=root))
    module=types.ModuleType('logipredict_main_contract_test');module.__path__=[str(reference)]
    sys.modules[module.__name__]=module
    import importlib
    main_schema=importlib.import_module(module.__name__+'.schema')
    main_service=importlib.import_module(module.__name__+'.service')
    pd.testing.assert_frame_equal(main_schema.feature_frame(rows),x)
    checks['actual_main_feature_contract']=True
    for label,app in [('candidate_service',create_app(release)),('unchanged_main_service',main_service.create_app(release))]:
        with TestClient(app) as client:
            assert client.get('/health').status_code==200
            assert client.get('/model').json()['threshold']==pipeline.threshold
            assert client.get('/analytics/states').json()['states']
            before=time.perf_counter()
            response=client.post('/predict',json=sample)
            latency=(time.perf_counter()-before)*1000
            assert response.status_code==200,response.text
            body=response.json()
            assert isinstance(body['predicted_late'],bool) and body['synthetic'] is False
            assert body['source']=='olist' and 0<=body['delay_probability']<=1 and 0<=body['threshold']<=1
            assert body['predicted_late']==(body['delay_probability']>=body['threshold'])
            np.testing.assert_allclose(body['delay_probability'],pipeline.predict_proba(feature_frame(payload))[0,1])
            assert client.post('/predict',json={**sample,'delivered_at':'2018-07-01'}).status_code==422
            assert client.post('/predict',json={**sample,'items_count':0}).status_code==422
            assert client.post('/predict',json={**sample,'seller_state':'XX'}).status_code==422
            missing={**sample,'distance_km':None,'total_weight_g':None,'total_volume_cm3':None}
            assert client.post('/predict',json=missing).status_code==200
            checks[label]={'status':'passed','first_request_ms':round(latency,2),'response':body}
    (work/'verification.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
    return checks
