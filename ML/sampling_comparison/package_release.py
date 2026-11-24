from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
import hashlib
root=Path(__file__).resolve().parent
reports=['plan.json','development_summary.csv','frozen_selection.json','final_results.csv',
         'verification.json','paired_uncertainty.csv','sampling_comparison.png','signature.json',
         'exemplo_vetores_sinteticos.csv','previous_sha256.json']
target=root/'Amostragem_Artificial_e_Limpeza_Completa.zip'
with ZipFile(target,'w',ZIP_DEFLATED) as archive:
    for p in root.iterdir():
        if p.is_file() and p.suffix in ['.py','.md','.toml','.json','.ipynb']:
            archive.write(p,str(Path(root.name)/p.name))
    for directory in ['sampling_risk','runtime_final','runtime_context','preservados','modelos_novos','training_inputs']:
        for p in sorted((root/directory).rglob('*')):
            if p.is_file() and '__pycache__' not in p.parts:
                archive.write(p,str(Path(root.name)/p.relative_to(root)))
    for name in reports:
        archive.write(root/'artifacts'/name,str(Path(root.name)/'reports'/name))
    for p in sorted((root/'artifacts/audits').glob('FINAL_*.json')):
        archive.write(p,str(Path(root.name)/'reports/audits'/p.name))
with ZipFile(target) as archive:assert archive.testzip() is None
print('Pacote:',target)
print('Bytes:',target.stat().st_size)
print('SHA256:',hashlib.sha256(target.read_bytes()).hexdigest())
