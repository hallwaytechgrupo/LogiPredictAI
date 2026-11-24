import os
for key in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:
    os.environ[key]='4'
from pathlib import Path
import joblib
from logipredict_final.refinements import run_refinements,run_maturity
if __name__=='__main__':
    work=Path(__file__).resolve().parent/'artifacts'
    run_refinements(joblib.load(work/'orders_clean.joblib'),work)
    run_maturity(joblib.load(work/'orders_clean.joblib'),work)
    print('Refinamento concluído.',flush=True)
