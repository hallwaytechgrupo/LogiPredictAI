"""Distribui notebook, fontes e pesos; não inclui CSVs nem caches de treino."""
from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
import hashlib,json

if __name__=='__main__':
    root=Path(__file__).resolve().parent
    report_files=['data_manifest.json','frozen_selection.json','development_summary.csv','final_comparison.csv',
        'main_comparison.json','cascade_audit.csv','verification.json','regional_report.csv','monthly_report.csv',
        'budget_500_diagnostic.json','uncertainty.json','tradeoff.png','run_signature.json','refinement_plan.json','maturity_plan.json']
    destination=root/'LogiPredict_Candidato_Completo.zip'
    with ZipFile(destination,'w',ZIP_DEFLATED) as archive:
        for path in sorted(root.iterdir()):
            if path.is_file() and path.suffix in ['.py','.toml','.md','.ipynb']:
                archive.write(path,str(Path(root.name)/path.name))
        for directory in ['logipredict_final','release']:
            for path in (root/directory).rglob('*'):
                if path.is_file() and '__pycache__' not in path.parts:
                    archive.write(path,str(Path(root.name)/path.relative_to(root)))
        for filename in report_files:
            path=root/'artifacts'/filename
            archive.write(path,str(Path(root.name)/'reports'/filename))
    print('Pacote:',destination)
    print('Bytes:',destination.stat().st_size)
    print('SHA256:',hashlib.sha256(destination.read_bytes()).hexdigest())
