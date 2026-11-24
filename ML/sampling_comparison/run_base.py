"""Permite executar referências independentes em processos separados."""
import os,sys
for key in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:os.environ[key]='4'
from pathlib import Path
import joblib
from sklearn import set_config
set_config(working_memory=128)
import sampling_risk.study as study
if __name__=='__main__':
    base=sys.argv[1];root=Path(__file__).resolve().parent;main=root/'artifacts'
    work=main/('by_'+base);work.mkdir(exist_ok=True)
    study.BASES={base:study.BASES[base]}
    b=joblib.load(main/'data.joblib');oof=joblib.load(root/'training_inputs/oof.joblib')
    study.run_development(b,oof,work)
    print('Referência concluída:',base,flush=True)
