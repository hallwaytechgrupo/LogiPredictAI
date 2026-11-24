"""Reúne avaliações independentes; não altera escolhas ou critérios."""
from pathlib import Path
import shutil,joblib,json
from sampling_risk.study import summarize
if __name__=='__main__':
    work=Path(__file__).resolve().parent/'artifacts'
    first_path=work/'base564_completed.joblib'
    if not first_path.exists():first_path=work/'by_base_564/development_records.joblib'
    first=joblib.load(first_path)
    first=[r for r in first if r['base']=='base_564']
    second=joblib.load(work/'by_base_613/development_records.joblib')
    assert len(first)==36 and len(second)==36,(len(first),len(second))
    (work/'audits').mkdir(exist_ok=True)
    for folder in [work/'by_base_564/audits',work/'by_base_613/audits']:
        for p in folder.glob('*.json'):shutil.copyfile(p,work/'audits'/p.name)
    rows=first+second;joblib.dump(rows,work/'development_records.joblib')
    summarize(rows,work)
    plan=json.loads((work/'plan.json').read_text(encoding='utf-8'))
    plan.update(parallel_references=2,threads_per_fit=4)
    (work/'plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
    print('72 avaliações reunidas; escolhas congeladas.')
