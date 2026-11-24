import os
for key in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:os.environ[key]='4'
from pathlib import Path
import joblib
import json,hashlib
from sampling_risk.evaluate import evaluate_final,export_models
from sampling_risk.checks import verify
from sampling_risk.reporting import report,paired_uncertainty
if __name__=='__main__':
    root=Path(__file__).resolve().parent;work=root/'artifacts'
    bundle=joblib.load(work/'data.joblib');oof=joblib.load(root/'training_inputs/oof.joblib')
    evaluate_final(bundle,oof,work)
    print('Modelos exportados:',export_models(work),flush=True)
    print('Verificações:',verify(work),flush=True)
    print('Incerteza:',paired_uncertainty(work).to_dict('records'),flush=True)
    print('Relatório:',report(work),flush=True)
    files=['resampling.py','study.py','evaluate.py']
    digest=hashlib.sha256(b''.join((root/'sampling_risk'/f).read_bytes() for f in files)).hexdigest()
    (work/'signature.json').write_text(json.dumps(dict(files=files,source_sha256=digest),indent=2),encoding='utf-8')
    print('Estudo concluído.',flush=True)
