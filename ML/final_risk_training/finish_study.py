"""Abre a avaliação final após a seleção temporal e exporta somente o candidato."""
import os
for variable in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:
    os.environ[variable]='4'
os.environ['MPLBACKEND']='Agg'
from pathlib import Path
import joblib,json,hashlib
from logipredict_final.evaluation import evaluate_selected,compare_shipped_model,export_selected
from logipredict_final.checks import verify
from logipredict_final.reporting import diagnostics,write_report

if __name__=='__main__':
    root=Path(__file__).resolve().parent;work=root/'artifacts'
    data=joblib.load(work/'orders_clean.joblib')
    result=evaluate_selected(data,work)
    print('ESCOLHA CONGELADA:',result['frozen'],flush=True)
    print('MAIN:',compare_shipped_model(data,work),flush=True)
    print('EXPORT:',export_selected(work)['version'],flush=True)
    print('CHECKS:',verify(work),flush=True)
    print('DIAGNOSTICS:',diagnostics(work)[1:],flush=True)
    print('RELATÓRIO:',write_report(work),flush=True)
    sources=['data.py','features.py','runtime.py','experiment.py','refinements.py','evaluation.py']
    signature=hashlib.sha256(b''.join((root/'logipredict_final'/p).read_bytes() for p in sources)).hexdigest()
    (work/'run_signature.json').write_text(json.dumps({'source_sha256':signature,'sources':sources},indent=2),encoding='utf-8')
    print('Finalização concluída.',flush=True)
