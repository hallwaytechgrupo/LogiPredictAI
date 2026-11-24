from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
import hashlib,json
root=Path(__file__).resolve().parent
files=['plan.json','development_summary.csv','frozen_selection.json','double_frozen.json',
       'final_results.csv','controls.csv','retention_profiles.csv','verification.json','comparison.png','signature.json']
destination=root/'Comparacao_Modelos_Contexto_Completa.zip'
with ZipFile(destination,'w',ZIP_DEFLATED) as archive:
    for path in root.iterdir():
        if path.is_file() and path.suffix in ['.py','.toml','.md','.json','.ipynb']:
            archive.write(path,str(Path(root.name)/path.name))
    for directory in ['context_risk','runtime_referencias','referencias','novos_modelos','training_inputs']:
        for path in sorted((root/directory).rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                archive.write(path,str(Path(root.name)/path.relative_to(root)))
    for name in files:
        archive.write(root/'artifacts'/name,str(Path(root.name)/'reports'/name))
with ZipFile(destination) as archive:assert archive.testzip() is None
print('ZIP:',destination)
print('Bytes:',destination.stat().st_size)
print('SHA256:',hashlib.sha256(destination.read_bytes()).hexdigest())
