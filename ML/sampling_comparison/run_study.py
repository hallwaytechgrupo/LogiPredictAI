import os
for key in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:os.environ[key]='4'
from pathlib import Path
import json,joblib
from sklearn import set_config
set_config(working_memory=128)
from sampling_risk.study import load_data,run_development,BASES,SPEC
from sampling_risk.resampling import METHODS
if __name__=='__main__':
    root=Path(__file__).resolve().parent;work=root/'artifacts'
    plan=dict(date='2026-11-22',bases=BASES,classifier=SPEC,methods=METHODS,seed=42,
        training_only=True,holdout='all 19258 real orders; no rows removed',
        scope='Only reviewer fitting changes; original detectors and genuine historical event store remain unchanged.')
    (work/'plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
    b=load_data(root);joblib.dump(b,work/'data.joblib',compress=3)
    oof=joblib.load(root/'training_inputs/oof.joblib')
    run_development(b,oof,work)
    print('Desenvolvimento concluído.',flush=True)
