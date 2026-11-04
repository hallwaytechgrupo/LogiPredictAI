# Contrato da API

Base local: `http://127.0.0.1:3001`. Serviço Python interno: `http://127.0.0.1:8000`. Sua documentação OpenAPI interativa fica em `http://127.0.0.1:8000/docs` e o schema em `/openapi.json`.

| Método | Rota pública Node.js | Função |
| --- | --- | --- |
| GET | `/health` | Processo da API disponível |
| GET | `/ready` | Serviço Python e modelo disponíveis |
| GET | `/api/v1/model` | Versão, origem, features, limiar e métricas do treinamento |
| POST | `/api/v1/predictions` | Classificação de um pedido no despacho |
| GET | `/api/v1/analytics/states` | Pedidos e atrasos observados por UF |
| GET | `/api/v1/orders` | Lista paginada de pedidos importados |
| POST | `/api/v1/orders/import` | Importa pedidos em lote |
| GET | `/api/v1/orders/:orderId` | Consulta um pedido por ID |
| PATCH | `/api/v1/orders/:orderId/hub` | Associa/dissocia hub a um pedido |

## Requisição de previsão

Use `Content-Type: application/json`. Exemplo completo: `examples/prediction.json`, na branch `back`. O arquivo `examples/api.http` pode ser usado com um cliente compatível com REST Client.

| Campo | Tipo | Regra |
| --- | --- | --- |
| `purchase_at` | data/hora | ISO 8601 local, sem sufixo Z ou offset |
| `dispatched_at` | data/hora | Não pode anteceder a compra |
| `estimated_delivery_at` | data/hora | Data de calendário não anterior à compra |
| `seller_state`, `customer_state` | texto | UF brasileira em maiúsculas |
| `distance_km` | número ou null | Entre 0 e 20.050; maior trajeto origem/destino |
| `total_weight_g` | número ou null | Total não negativo em gramas |
| `total_volume_cm3` | número ou null | Total não negativo em cm³ |
| `items_count`, `sellers_count` | inteiro | De 1 a 10.000; vendedores não podem exceder itens |
| `price`, `freight_value` | número | Total não negativo em reais |

Distância, peso e volume podem ser omitidos ou receber null; o pipeline usa a estatística aprendida no treino e retorna um aviso. Outros campos são obrigatórios. Campos extras, inclusive entrega real e rótulo, são rejeitados. Na primeira versão, a entrada já contém os agregados do pedido; não há consulta a CEP nem montagem automática do pedido pela API.

```powershell
$body = Get-Content examples/prediction.json -Raw
Invoke-RestMethod http://127.0.0.1:3001/api/v1/predictions -Method Post -ContentType 'application/json' -Body $body
```

Retorno ilustrativo (valores variam conforme o modelo):

```json
{
  "model_version": "rf-olist-<hash-do-dataset>",
  "source": "olist",
  "synthetic": false,
  "delay_probability": 0.42,
  "threshold": 0.35,
  "predicted_late": true,
  "warnings": ["Score não calibrado; validar antes de uso operacional."]
}
```

`predicted_late` compara o score ao limiar selecionado na validação. O modelo não estima uma nova data de entrega. Leia as limitações probabilísticas em `docs/data-science.md`.

## Erros

| HTTP | Significado |
| --- | --- |
| 400 | JSON malformado |
| 404 | Rota inexistente |
| 413 | Payload maior que 32 KB |
| 415 | Corpo enviado com mídia diferente de application/json |
| 422 | Dados inválidos; `details` identifica os campos |
| 502 | Serviço Python respondeu com erro inesperado |
| 503 | Modelo ausente ou serviço Python indisponível |
| 504 | Serviço Python excedeu o timeout |

O Node não repassa os valores de entrada anexados às mensagens de erro do Pydantic. Não há registro persistente das requisições nesta fase.

## Configuração

Copie `api/.env.example` para `api/.env` se precisar alterar host, porta, endereço do serviço interno ou timeout. Os scripts `npm start` e `npm run dev` leem esse arquivo quando executados na pasta `api`. O Python lê `MODEL_DIR` do ambiente; por padrão, `models/olist` relativo à pasta de execução.

## Listagem de pedidos

`GET /api/v1/orders` retorna os pedidos importados via `POST /api/v1/orders/import`, com paginação e filtros opcionais.

### Parâmetros de consulta

| Parâmetro | Tipo | Padrão | Máximo | Descrição |
| --- | --- | --- | --- | --- |
| `page` | inteiro | 1 | 9999 | Número da página |
| `per_page` | inteiro | 50 | 500 | Itens por página |
| `hub_id` | texto | — | — | Filtra por hub associado |
| `q` | texto | — | — | Busca texto contido no `order_id` |

### Exemplo de resposta

```json
{
  "data": [
    {
      "order_id": "order-001",
      "hub_id": "hub-stable-id-1",
      "hub": {
        "id": "hub-stable-id-1",
        "code": "HUB-01",
        "name": "Hub São Paulo",
        "city": "São Paulo",
        "state": "SP"
      },
      "source": "olist",
      "createdAt": "2025-06-15T12:00:00.000Z",
      "updatedAt": "2025-06-15T12:00:00.000Z"
    }
  ],
  "total": 1,
  "page": 1,
  "per_page": 50,
  "total_pages": 1
}
```

### Erros específicos

| HTTP | Código | Significado |
| --- | --- | --- |
| 422 | `INVALID_PAGE` | `page` ou `per_page` inválido |
| 422 | `INVALID_HUB_ID` | `hub_id` não é uma string válida |
| 500 | `ORDER_STORAGE_ERROR` | Falha ao ler `orders.json` |

### Configuração Flutter

A URL base é configurada via `--dart-define=API_BASE_URL=http://127.0.0.1:3001`. No Android emulador, use `http://10.0.2.2:3001` para acessar o host.
