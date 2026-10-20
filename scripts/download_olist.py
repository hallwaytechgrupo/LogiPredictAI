"""Baixa a versão 2 da fonte oficial. Se Kaggle exigir login, use o download manual."""
import argparse
import hashlib
import json
import shutil
import urllib.request
import zipfile
from pathlib import Path

URL = "https://www.kaggle.com/api/v1/datasets/download/olistbr/brazilian-ecommerce?datasetVersionNumber=2"
TABLES = ["orders", "order_items", "customers", "sellers", "products", "geolocation"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("data/raw"))
    parser.add_argument("--archive", type=Path, help="ZIP já baixado; evita novo download.")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.archive or args.output / "olist.zip"
    if not args.archive:
        print("Baixando Olist v2 do Kaggle (aprox. 43 MB compactados)...")
        request = urllib.request.Request(URL, headers={"User-Agent": "LogiPredictAI/0.1"})
        with urllib.request.urlopen(request, timeout=120) as response, archive.open("wb") as target:
            shutil.copyfileobj(response, target)
    if not zipfile.is_zipfile(archive):
        raise SystemExit("Resposta não é ZIP. Baixe manualmente no Kaggle; consulte data/README.md.")
    files = [f"olist_{table}_dataset.csv" for table in TABLES]
    with zipfile.ZipFile(archive) as zipped:
        if not set(files).issubset(zipped.namelist()):
            raise SystemExit("ZIP não contém os seis CSVs esperados da Olist v2.")
        for name in files:
            target = args.output / name
            if target.exists():
                raise SystemExit(f"Arquivo já existe: {target}. Use uma pasta nova para evitar sobrescrita.")
        for name in files:
            # Apenas nomes conhecidos, sem extractall nem caminhos fornecidos pelo arquivo ZIP.
            with zipped.open(name) as source, (args.output / name).open("wb") as target:
                shutil.copyfileobj(source, target)
    receipt = {"dataset": "olistbr/brazilian-ecommerce", "version": 2, "url": URL,
               "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(), "files": files}
    (args.output / "source.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(f"Seis tabelas extraídas em {args.output}. Dados brutos não devem ser commitados.")


if __name__ == "__main__":
    main()
