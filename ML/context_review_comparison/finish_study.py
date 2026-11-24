import os
for key in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:os.environ[key]='4'
from pathlib import Path
import joblib
import json,hashlib
from context_risk.double_review import run_double_development
from context_risk.evaluate import evaluate_final,export_models
from context_risk.checks import verify
from context_risk.reporting import report
from context_risk.profiles import export_profiles
if __name__=='__main__':
    work=Path(__file__).resolve().parent/'artifacts';b=joblib.load(work/'data_context.joblib')
    run_double_development(b['data'],b['context'],work)
    evaluate_final(b['data'],b['context'],b['history'],work)
    print('Exportação:',export_models(work),flush=True)
    print('Perfis extras:',export_profiles(work),flush=True)
    print('Auditoria:',verify(work),flush=True)
    print('Relatório:',report(work),flush=True)
    files=['history.py','runtime.py','study.py','double_review.py','evaluate.py']
    digest=hashlib.sha256(b''.join((work.parent/'context_risk'/f).read_bytes() for f in files)).hexdigest()
    (work/'signature.json').write_text(json.dumps({'source_sha256':digest,'files':files},indent=2),encoding='utf-8')
    print('Estudo concluído.',flush=True)
