# Resultados da validação — Simulador de Previsão de Atrasos

Data da execução: 2026-11-22.

## Ambiente e serviços

- Flutter 3.47.9 / Dart 3.13.7.
- Node.js v24.13.0.
- Python 3.12.3.
- Frontend Flutter: HTTP 200 em `127.0.0.1:8080` — PASSOU.
- Node.js: HTTP 200 em `/health` — PASSOU.
- Node.js `/ready`: HTTP 200, modelo `rf-olist-b96c2d0272d8`, `synthetic: false` — PASSOU.
- FastAPI direto em `127.0.0.1:8000`: conexão recusada — NÃO EXECUTADO.

Os serviços já estavam ativos. Nenhum serviço novo foi iniciado, nenhuma
dependência foi instalada e nenhum treinamento ou migration foi executado.

Artefato confirmado:

```text
back/ml/models/olist/model.joblib — 9,1 MB
versão: rf-olist-b96c2d0272d8
fonte: olist
```

## Geolocalização real

Requisição com origens `01001-000`, `01002-000` e destino `40010-000`:

- HTTP 200 — PASSOU.
- origem: SP;
- destino: BA;
- distância Haversine: `1454.7046688306546 km`;
- duas origens/vendedores reconhecidos;
- fonte: base Olist geolocation.

O CEP `40000-000` não foi encontrado na base local e retornou HTTP 404.

## Cenário base real

Payload enviado a `POST /api/v1/predictions`, sem `order_id`:

```json
{
  "purchase_at": "2018-01-01T08:00:00",
  "dispatched_at": "2018-01-02T08:00:00",
  "estimated_delivery_at": "2018-01-08T08:00:00",
  "seller_state": "SP",
  "customer_state": "BA",
  "distance_km": 1454.7046688306546,
  "total_weight_g": 2500,
  "total_volume_cm3": 120,
  "items_count": 2,
  "sellers_count": 2,
  "price": 100.0,
  "freight_value": 10.0
}
```

Resultado observado: HTTP 200 — PASSOU.

- score: `0.42090540888847977`;
- classificação: `predicted_late: true`;
- threshold: `0.36999999999999994`;
- modelo: `rf-olist-b96c2d0272d8`;
- warnings: previsão agregada por pedido e score não calibrado.

## Cenário alternativo real

Foi alterada somente a data do despacho:

```text
base:        2018-01-02T08:00:00
alternativo: 2018-01-03T08:00:00
```

Resultado observado: HTTP 200 — PASSOU.

- score: `0.4313890045277873`;
- classificação: `predicted_late: true`;
- threshold: `0.36999999999999994`;
- modelo: `rf-olist-b96c2d0272d8`;
- warnings: iguais ao cenário base.

Diferença calculada por `SimulatorComparison`:

```text
(0.4313890045277873 - 0.42090540888847977) × 100
= +1.048359563930752 pontos percentuais
```

Essa diferença é apenas uma diferença entre scores do modelo; não comprova
causalidade nem garante mudança real na entrega.

## Persistência

Foi feita verificação somente de leitura antes e depois de uma previsão sem
`order_id`:

- `back/data/hubs/predictions.json`: tamanho e SHA-256 inalterados;
- `back/data/hubs/predictions.jsonl`: tamanho e SHA-256 inalterados.

Não foi criado pedido nem alterado banco. A ausência de persistência em
PostgreSQL não foi auditada diretamente: status **NÃO VERIFICADO**.

## Despacho e mapa

`POST /api/v1/dispatch/simulate` com `01001-000` → `01002-000` respondeu HTTP
200 — PASSOU, retornando hubs, distâncias e aviso de mesmo hub.

O frontend respondeu HTTP 200, mas a inspeção visual no navegador não foi
executada. Logo, o mapa e a apresentação visual estão **NÃO EXECUTADOS**.

A previsão alternativa foi chamada diretamente em `/api/v1/predictions` e não
executou o endpoint de despacho.

## Testes de falha

| Teste | Resultado | Status |
|---|---|---|
| Payload incompleto | HTTP 422 `VALIDATION_ERROR` | PASSOU |
| CEP inválido | HTTP 422 `INVALID_CEP` | PASSOU |
| FastAPI direto no host | Porta 8000 inacessível | NÃO EXECUTADO |
| Serviço ML indisponível | Não provocado | NÃO EXECUTADO |
| Timeout real | Não provocado | NÃO EXECUTADO |
| Alteração durante carregamento | Não executada visualmente | NÃO EXECUTADO |
| Restauração visual | Não executada visualmente | NÃO EXECUTADO |
| Pedido importado | Não executado visualmente | NÃO EXECUTADO |

Concorrência, restauração e falhas independentes possuem cobertura unitária no
controlador, mas não foram validadas visualmente com serviços reais.

## Testes automatizados

Com Flutter absoluto e `--no-pub`, a suíte completa foi executada:

```text
86 testes chegaram a ser executados; 83 passaram e 3 falharam.

Falhas observadas:

- `map_scenarios_test.dart`: falha por múltiplas exceções de tiles do
  OpenStreetMap retornando HTTP 400 e falha no caso de formulário de mapa.
- `orders_front_integration_test.dart`: não encontrou o texto esperado
  `O modelo classificou risco de atraso`.

Essas falhas não foram corrigidas nesta etapa, conforme a restrição de não
alterar código sem aprovação. A suíte reduzida usada anteriormente para os
modelos/controlador havia passado, mas isso não equivale à suíte completa.
```

A análise estática não encontrou erros de compilação. Foram reportados 29
avisos/informações de estilo e código legado, como campos não utilizados,
sugestões de `const` e `withOpacity` depreciado.

## Limitações

- Nenhuma instância nova foi iniciada.
- A porta direta do FastAPI não está publicada no host.
- Não houve teste visual manual no navegador.
- PostgreSQL não foi alterado nem verificado diretamente.
- A cadeia foi validada por Node `/ready` e respostas reais de previsão, mas a
  interface visual ainda requer validação manual.
