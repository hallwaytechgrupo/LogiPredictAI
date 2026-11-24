"""Execução reproduzível; o notebook usa os mesmos arquivos e funções."""
import os
for variable in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:
    os.environ[variable]='4'
from pathlib import Path
import json,joblib,time
from logipredict_final.data import load_orders
from logipredict_final.experiment import run_development

if __name__=='__main__':
    work=Path(__file__).resolve().parent/'artifacts'
    work.mkdir(exist_ok=True)
    began=time.perf_counter()
    data,manifest=load_orders()
    joblib.dump(data,work/'orders_clean.joblib')
    (work/'data_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(manifest['quality'],flush=True)
    print('Teste final reservado a partir de',data.dispatched_at.iloc[int(len(data)*.8)],flush=True)
    run_development(data,work)
    print(f'Desenvolvimento concluído em {time.perf_counter()-began:.1f}s',flush=True)
