from pathlib import Path
import os,sys,json,asyncio
if sys.platform=='win32':asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
import nbformat
from nbclient import NotebookClient
root=Path(__file__).resolve().parent
directory=root/'artifacts/jupyter';kernel=directory/'kernels/logipredict-contexto'
kernel.mkdir(parents=True,exist_ok=True)
(kernel/'kernel.json').write_text(json.dumps({'argv':[sys.executable,'-X','utf8','-m','ipykernel_launcher','-f','{connection_file}'],
    'display_name':'Python LogiPredict contexto','language':'python'}),encoding='utf-8')
os.environ['JUPYTER_PATH']=str(directory)
for path in sorted((root/'referencias').rglob('*.ipynb')):
    nb=nbformat.read(path,as_version=4)
    NotebookClient(nb,timeout=300,kernel_name='logipredict-contexto',resources={'metadata':{'path':str(path.parent)}}).execute()
    nbformat.write(nb,path)
    print('Referência executada:',path.name,flush=True)
