"""Gera um catálogo compacto de locais reais; não gera pedidos nem rótulos."""

import hashlib
import json
from pathlib import Path

import pandas as pd


def build(raw, output):
    raw, output = Path(raw), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    geo_file = raw / "olist_geolocation_dataset.csv"
    seller_file = raw / "olist_sellers_dataset.csv"
    geo = pd.read_csv(
        geo_file, dtype={"geolocation_zip_code_prefix": str}
    ).drop_duplicates()
    geo["prefix5"] = geo.geolocation_zip_code_prefix.str.zfill(5)
    # Mesmos limites geográficos do treinamento final, sem pontos fora do Brasil.
    geo = geo[
        geo.geolocation_lat.between(-35, 6) & geo.geolocation_lng.between(-75, -28)
    ]
    grouped = geo.groupby("prefix5", sort=True)
    coordinates = grouped[["geolocation_lat", "geolocation_lng"]].median()
    coordinates.columns = ["latitude", "longitude"]
    # UF e cidade são as ocorrências mais frequentes; o ponto representa um prefixo,
    # não o endereço exato de uma pessoa ou o traçado de uma rodovia.
    labels = grouped[["geolocation_state", "geolocation_city"]].agg(
        lambda x: x.mode().iloc[0]
    )
    labels.columns = ["state", "city"]
    places = coordinates.join(labels).reset_index()
    places.to_csv(
        output / "locations.csv.gz",
        index=False,
        compression={"method": "gzip", "mtime": 0},
    )
    sellers = pd.read_csv(seller_file, dtype={"seller_zip_code_prefix": str})
    sellers = sellers.rename(
        columns={
            "seller_zip_code_prefix": "prefix5",
            "seller_state": "state",
            "seller_city": "city",
        }
    )
    sellers.prefix5 = sellers.prefix5.str.zfill(5)
    sellers.to_csv(
        output / "sellers.csv.gz",
        index=False,
        compression={"method": "gzip", "mtime": 0},
    )
    manifest = {
        "source": "olist",
        "locations": len(places),
        "sellers": len(sellers),
        "coordinates": "Median of distinct valid Olist geolocation rows by five-digit ZIP prefix",
        "raw_sha256": {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [geo_file, seller_file]
        },
        "sha256": {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in output.glob("*.csv.gz")
        },
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Catálogo real: {len(places)} prefixos e {len(sellers)} vendedores.")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--raw", type=Path, default=Path(__file__).resolve().parents[2] / "data/raw"
    )
    parser.add_argument(
        "--output", type=Path, default=Path(__file__).resolve().parents[1] / "map_data"
    )
    args = parser.parse_args()
    build(args.raw, args.output)
