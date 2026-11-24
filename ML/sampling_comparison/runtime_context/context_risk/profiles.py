"""Cortes predefinidos do filtro 614; não reajusta pesos nem otimiza no teste."""
from pathlib import Path
import copy,json
import joblib

def export_profiles(work):
    work=Path(work);r=joblib.load(work/'final.joblib')
    original=joblib.load(work.parent/'novos_modelos/modelo_614_filter/model.joblib')
    selected=r['retentions'].loc[r['retentions'].name.eq('modelo_614_filter')]
    data=joblib.load(work/'data_context.joblib')['data'].loc[r['test_index']]
    outputs=[]
    for retention,suffix in [(.975,'975'),(.95,'95')]:
        row=selected.loc[selected.calibration_retention.eq(retention)].iloc[0]
        pipeline=copy.copy(original['pipeline']);pipeline.threshold=float(row.threshold)
        metadata={**original['metadata'],'version':'modelo_614_filter_retain'+suffix,
                  'threshold':pipeline.threshold,'metrics':row.to_dict(),'calibration_retention':retention}
        directory=work.parent/'novos_modelos'/metadata['version'];directory.mkdir(exist_ok=True)
        joblib.dump({'pipeline':pipeline,'metadata':metadata},directory/'model.joblib',compress=3)
        (directory/'metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
        p=r['scores']['modelo_614_filter'];decision=p>=pipeline.threshold;y=data.is_late.to_numpy()
        assert int((decision&(y==1)).sum())==row.TP
        assert int((decision&(y==0)).sum())==row.FP
        outputs.append(str(directory))
    return outputs
