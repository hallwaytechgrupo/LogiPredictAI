"""Executa o notebook no mesmo Python do estudo e grava saídas verificáveis."""
from pathlib import Path
import os,json,sys
os.environ['MPLBACKEND']='Agg'
if sys.platform=='win32':
    import asyncio
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
import nbformat
from nbclient import NotebookClient

if __name__=='__main__':
    root=Path(__file__).resolve().parent
    # Kernel local ao estudo; não altera a lista de kernels do usuário.
    directory=root/'artifacts'/'jupyter'
    kernel=directory/'kernels'/'logipredict-amostragem'
    kernel.mkdir(parents=True,exist_ok=True)
    (kernel/'kernel.json').write_text(json.dumps({
        'argv':[sys.executable,'-X','utf8','-m','ipykernel_launcher','-f','{connection_file}'],
        'display_name':'Python LogiPredict final','language':'python'}),encoding='utf-8')
    os.environ['JUPYTER_PATH']=str(directory)
    path=root/'Teste_Amostragem_Artificial_e_Limpeza.ipynb'
    notebook=nbformat.read(path,as_version=4)
    client=NotebookClient(notebook,timeout=1800,kernel_name='logipredict-amostragem',
        resources={'metadata':{'path':str(root)}})
    client.execute()
    nbformat.write(notebook,path)
    errors=[output for cell in notebook.cells if cell.cell_type=='code'
            for output in cell.get('outputs',[]) if output.output_type=='error']
    assert not errors,errors
    print('Notebook executado sem erros:',sum(c.cell_type=='code' for c in notebook.cells),'células de código.',flush=True)
