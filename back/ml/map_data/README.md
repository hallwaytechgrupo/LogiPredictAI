# Catálogo geográfico real do mapa

Dados derivados dos CSVs públicos Olist presentes em `back/data/raw`.
Origem geral e atribuição em [Dados](../../../data/README.md).

- `locations.csv.gz`: 19.011 prefixos CEP com coordenadas válidas. Mediana de
  latitude/longitude após deduplicação e aplicação dos limites geográficos do
  treinamento final; cidade/UF por ocorrência mais frequente.
- `sellers.csv.gz`: 3.095 identificadores reais de vendedores, com cidade, UF
  e prefixo CEP preservando zeros à esquerda.
- `manifest.json`: hashes dos CSVs originais e dos arquivos derivados.

Não são endereços exatos nem novos pedidos. Não há geração de alvos de atraso.
O catálogo é carregado localmente e dispensa APIs externas de CEP para esse fluxo.

Reprodução, na raiz do repositório:

```powershell
$env:PYTHONPATH = 'back/ml'
.\.venv\Scripts\python.exe -m logipredict.build_map_catalog
```
