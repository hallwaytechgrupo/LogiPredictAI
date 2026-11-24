import os
for key in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:os.environ[key]='4'
from pathlib import Path
import json,joblib
from context_risk.study import generate_oof,run_development,SPECS,REFS,OOF_STARTS,MAIN_RETENTION
if __name__=='__main__':
    work=Path(__file__).resolve().parent/'artifacts';bundle=joblib.load(work/'data_context.joblib')
    (work/'plan.json').write_text(json.dumps(dict(references=REFS,specs=SPECS,main_retention=MAIN_RETENTION,
        oof_months=[str(d) for d in OOF_STARTS],selection='four temporal development months; frozen before new final metrics',
        history='completed deliveries strictly before each dispatch; prequential with observed events, no weight updates'),indent=2),encoding='utf-8')
    if not (work/'oof.joblib').exists():generate_oof(bundle['data'],work)
    run_development(bundle['data'],bundle['context'],work)
    print('Seleção concluída.',flush=True)
