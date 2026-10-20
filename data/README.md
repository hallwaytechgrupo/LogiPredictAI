# Base de dados Olist

Fonte: [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), versão 2, pedidos brasileiros de 2016 a 2018.

Na raiz do projeto, após instalar o ambiente Python:

```powershell
.\.venv\Scripts\python.exe scripts/download_olist.py
```

O script usa o endpoint público oficial do Kaggle. Se houver exigência de login ou indisponibilidade, baixe o ZIP pela página do dataset e use:

```powershell
.\.venv\Scripts\python.exe scripts/download_olist.py --archive "C:\Downloads\archive.zip"
```

Alternativamente, extraia manualmente estes seis arquivos diretamente em `data/raw/`:

| Arquivo | Finalidade |
| --- | --- |
| `olist_orders_dataset.csv` | Datas de compra, despacho, promessa e entrega; status para seleção |
| `olist_order_items_dataset.csv` | Itens, vendedores, preço e frete |
| `olist_customers_dataset.csv` | UF e prefixo de CEP do destino |
| `olist_sellers_dataset.csv` | UF e prefixo de CEP da origem |
| `olist_products_dataset.csv` | Peso e dimensões dos produtos |
| `olist_geolocation_dataset.csv` | Coordenadas aproximadas por prefixo de CEP |

Pagamentos, avaliações e tradução de categorias não são necessários nesta versão. Avaliações pós-entrega não entram no treinamento.

O download registra URL, versão e SHA-256 do ZIP em `data/raw/source.json`. Não publica os arquivos. O treinamento também registra o hash do CSV processado em seus metadados.

## Processamento

```powershell
.\.venv\Scripts\python.exe -m logipredict.prepare
```

Produz `data/processed/orders.csv` e `orders.quality.json`. Veja critérios, features e limitações em `docs/data-science.md`.

## Demonstração sem baixar a base

```powershell
.\.venv\Scripts\python.exe -m logipredict.demo
.\.venv\Scripts\python.exe -m logipredict.train --input data/processed/demo.csv --source synthetic --model-dir models/demo --report-dir reports/local/demo
```

Esse gerador produz registros artificiais. Seus resultados validam instalação e integração, sem sustentar conclusões sobre logística brasileira. Use `MODEL_DIR=models/demo` apenas para essa demonstração.
