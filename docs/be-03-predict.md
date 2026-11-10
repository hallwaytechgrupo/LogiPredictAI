# BE-03 · POST /predict com referência histórica Olist

`POST http://127.0.0.1:3001/predict` classifica risco de atraso por regras determinísticas sobre tempos de transporte observados. O backend Node lê uma tabela agregada gerada offline pelo ETL Python existente. A execução da regra depende dessa tabela e dos três campos recebidos.

A fonte é o Brazilian E-Commerce Public Dataset by Olist. A publicação reúne pedidos de 2016–2018. Os seis CSVs locais utilizados têm seus hashes SHA-256 registrados em `back/src/data/predict-reference.json`, junto com a versão das regras, contagens e período observado. [Dataset publicado pela Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce).

O ETL lê pedidos, itens, produtos, vendedores, clientes e geolocalização. Agrega peso por pedido e calcula a maior distância Haversine vendedor–cliente entre os itens. A duração histórica é `data_da_entrega - data_do_despacho`, em dias de calendário. Entrega e despacho no mesmo dia produzem duração zero.

Dos 99.441 pedidos brutos, o ETL mantém 96.281 entregues elegíveis. O BE-03 usa apenas entregas observadas **antes de 01/03/2018**. Dos 53.620 pedidos nesse corte, 293 têm peso ou distância incompletos. A referência contém **53.327 pedidos completos**, com despachos de 08/10/2016 a 27/02/2018 e entregas até 28/02/2018. Esse corte antecede a validação e o teste temporal do experimento ML atual. Informações posteriores ao corte ficam fora dos percentis.

Os limites das faixas, o mínimo de 100 observações e os percentis 50/90 são escolhas demonstrativas de implementação. Os tempos em cada faixa são calculados dos registros reais. A contagem mínima limita o uso de grupos pequenos e continua exigindo avaliação estatística e operacional.

| Distância em km | Peso total em g | Pedidos | P50 em dias | P90 em dias |
| --- | --- | ---: | ---: | ---: |
| 0 a 250 | até 1.000 | 8.602 | 3 | 9 |
| 0 a 250 | acima de 1.000 até 5.000 | 3.800 | 4 | 10 |
| 0 a 250 | acima de 5.000 | 2.015 | 4 | 12 |
| acima de 250 até 750 | até 1.000 | 13.035 | 8 | 16 |
| acima de 250 até 750 | acima de 1.000 até 5.000 | 7.684 | 8 | 17 |
| acima de 250 até 750 | acima de 5.000 | 3.389 | 8 | 18 |
| acima de 750 até 1.500 | até 1.000 | 5.480 | 10 | 20 |
| acima de 750 até 1.500 | acima de 1.000 até 5.000 | 3.052 | 10 | 20 |
| acima de 750 até 1.500 | acima de 5.000 | 1.330 | 11 | 22 |
| acima de 1.500 | até 1.000 | 2.846 | 14 | 28 |
| acima de 1.500 | acima de 1.000 até 5.000 | 1.443 | 14 | 28 |
| acima de 1.500 | acima de 5.000 | 651 | 15 | 29 |

Cada limite superior pertence à faixa correspondente. Por exemplo, 250 km e 1.000 g pertencem à primeira linha. Percentis usam `interpolation="higher"` do pandas, selecionando um tempo efetivamente observado. Os valores da tabela correspondem à versão `be03-olist-v1-380e3dfdaf83`.

| Condição sobre o prazo disponível | Risco |
| --- | --- |
| `remaining_days < P50` | Alto |
| `P50 <= remaining_days < P90` | Médio |
| `remaining_days >= P90` | Baixo |

Se uma referência regenerada tiver menos de 100 pedidos na faixa combinada, o serviço tenta a faixa de distância e depois o agregado global. A resposta identifica a abrangência utilizada e inclui um aviso. A referência atual tem pelo menos 651 pedidos em cada uma das 12 combinações. Entradas fora dos mínimos/máximos observados recebem aviso de extrapolação.

Envie `Content-Type: application/json` com os três campos abaixo.

| Campo | Validação e unidade |
| --- | --- |
| `total_weight_g` | Número finito maior que zero, em gramas |
| `distance_km` | Número finito de 0 a 20.050, em quilômetros de distância Haversine |
| `remaining_days` | Inteiro não negativo de dias de calendário entre despacho e data prometida |

`remaining_days: 0` representa entrega prevista para o próprio dia do despacho. Converta quilogramas para gramas antes do envio. Campos ausentes, nulos, textos numéricos, booleanos, campos adicionais e valores fora desses limites produzem HTTP 422 com `VALIDATION_ERROR` e `details` por campo.

No Git Bash, inicie o backend a partir da raiz do projeto.

```bash
cd back
npm ci
npm start
```

Em outro terminal, execute a requisição.

```bash
curl -sS http://127.0.0.1:3001/predict \
  -H 'Content-Type: application/json' \
  -d '{"total_weight_g":500,"distance_km":100,"remaining_days":5}'
```

Esse exemplo retorna `risk: "Médio"`. A referência selecionada contém 8.602 pedidos, P50 de 3 dias e P90 de 9 dias. Com o mesmo peso e distância, prazo de 2 dias retorna Alto e prazo de 9 dias retorna Baixo.

O JSON inclui `risk`, `method: "historical_rules"`, `rules_version`, `source: "olist"`, `synthetic: false`, `input`, `rule`, `reference` e `warnings`. Em `reference`, `level` informa `distance_weight`, `distance` ou `global`, e os índices `distance_band` e `weight_band` identificam as faixas solicitadas a partir de zero. Também são retornados tamanho da amostra, P50/P90, extremos observados, período, corte e URL da fonte. O campo `synthetic: false` identifica a origem histórica dos agregados.

JSON malformado produz HTTP 400. Mídia diferente de JSON produz HTTP 415. Aplica-se o limite global de corpo de 2 MB, com HTTP 413. Referência ausente ou inválida produz HTTP 503 com `RISK_REFERENCE_UNAVAILABLE`. O carregamento da referência ocorre na primeira consulta válida, fica em memória e é tentado novamente após falhas. Reinicie o Node após uma regeneração bem-sucedida para carregar a nova versão.

Para reproduzir a referência, disponibilize os seis CSVs oficiais em `back/data/raw` e instale as dependências Python já usadas pelo ETL. A partir da raiz, no Git Bash, execute o comando abaixo.

```bash
PYTHONPATH=back/ml .venv/Scripts/python.exe -m logipredict.build_risk_reference
```

O comando reutiliza `prepare.py` e grava apenas o agregado em `back/src/data/predict-reference.json`, por substituição de arquivo temporário. O hash da versão considera fontes, estatísticas e política. Com os mesmos arquivos e transformações, a geração é determinística. O Dockerfile atual já copia `src`, incluindo esse JSON. A API pode executar a regra com esse agregado distribuído no código. Para usar outro arquivo, configure `PREDICT_REFERENCE_FILE` antes de iniciar a API.

A implementação está dividida entre `routes/predict.js`, responsável pelo HTTP, `risk.js`, responsável por validação e classificação, e `build_risk_reference.py`, responsável pela agregação offline. Uma evolução para um preditor pode ser implementada atrás da rota e deve declarar seu método e versionamento na resposta.

Os testes BE-03 cobrem todas as faixas reais, os limites dos percentis, validações, fallback, extrapolação, concorrência de leitura, indisponibilidade e recuperação da referência, corte temporal e compatibilidade do proxy existente. Execute os comandos na raiz.

```bash
npm --prefix back test
PYTHONPATH=back/ml .venv/Scripts/python.exe -m pytest back/ml/tests/test_risk_reference.py -q
```

As limitações afetam a interpretação do resultado. A unidade histórica é o pedido, que pode conter vários itens e vendedores, portanto o peso de um pacote isolado é uma aproximação dessa unidade. A distância é em linha reta. Transporte rodoviário, transportadora, modalidade, região específica, clima, feriados e mudanças operacionais atuais ficam fora das regras. A seleção de entregues exclui cancelamentos, extravios e pedidos sem desfecho. O corte também exclui entregas que ainda estavam em andamento.

Os percentis descrevem a duração de transporte da amostra. A classificação exige avaliação futura em dados separados antes de orientar decisões operacionais. P50 e P90 expressam posições na distribuição histórica e a resposta apresenta uma categoria demonstrativa de risco. Ainda faltam métricas de desempenho e calibração para estimar a chance individual de atraso.
