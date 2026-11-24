import os
for key in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:os.environ[key]='4'
from pathlib import Path
import json,joblib,time
from logipredict_final.data import load_orders
from context_risk.history import HistoryStore
if __name__=='__main__':
    root=Path(__file__).resolve().parent;work=root/'artifacts';work.mkdir(exist_ok=True)
    began=time.perf_counter()
    data,manifest=load_orders()
    old=json.loads((root/'training_inputs/data_manifest.json').read_text(encoding='utf-8'))
    assert manifest==old,'A origem dos dados mudou; a comparação deve ser revista.'
    store=HistoryStore.from_orders(data)
    print('Construindo histórico causal para',len(data),'pedidos...',flush=True)
    context=store.query(data)
    joblib.dump(dict(data=data,manifest=manifest,history=store,context=context),work/'data_context.joblib',compress=3)
    print('Contexto pronto:',context.shape,'tempo',round(time.perf_counter()-began,1),'s',flush=True)
