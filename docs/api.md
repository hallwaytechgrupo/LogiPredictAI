# Contrato da API

Base local: `http://127.0.0.1:3001`. Serviço Python interno: `http://127.0.0.1:8000`. Sua documentação OpenAPI interativa fica em `http://127.0.0.1:8000/docs` e o schema em `/openapi.json`.

| Método | Rota pública Node.js | Função |
| --- | --- | --- |
| GET | `/health` | Processo da API disponível |
| GET | `/ready` | Serviço Python e modelo disponíveis |
| POST | `/predict` | Risco Baixo, Médio ou Alto por regras com referência histórica Olist |
| GET | `/api/v1/model` | Versão, origem, features, limiar e métricas do treinamento |
| POST | `/api/v1/predictions` | Classificação de um pedido no despacho |
| GET | `/api/v1/analytics/states` | Pedidos e atrasos observados por UF |
| GET | `/api/v1/orders` | Lista paginada de pedidos importados |
| POST | `/api/v1/orders/import` | Importa pedidos em lote |
| GET | `/api/v1/orders/:orderId` | Consulta um pedido por ID |
| PATCH | `/api/v1/orders/:orderId/hub` | Associa/dissocia hub a um pedido |

O contrato BE-03 recebe `total_weight_g`, `distance_km` e `remaining_days` na porta 3001. As regras, dados observados, exemplos e limitações estão em [BE-03 · POST /predict](be-03-predict.md).

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

`GET /api/v1/orders` retorna os pedidos persistidos, com paginação e filtros opcionais. O CSV operacional é recebido em `POST /api/v1/orders/import-csv` como `{ "csv": "conteúdo do arquivo" }`. A importação por IDs em `/api/v1/orders/import` também está disponível.

O arquivo `back/data/exemplos_fe04_be02.csv` contém cinco pedidos fictícios para importar pela aba Pedidos. Seus IDs começam com `DEMO-FE04-` e permitem demonstrar FE-04 e BE-02. A importação repetida preserva os pedidos existentes e informa os IDs ignorados.

O CSV de exemplo usa ponto e vírgula como separador para a abertura em colunas no Excel com configuração regional brasileira. A leitura de CSV no Flutter e a importação de pedidos no Node identificam vírgula ou ponto e vírgula pelo cabeçalho. Campos entre aspas e vírgulas decimais nos arquivos separados por ponto e vírgula são preservados.

Os CEPs do exemplo usam hífen, como `01001-000`, para preservar o zero inicial ao abrir e salvar no Excel. A API aceita esse formato e armazena os oito dígitos normalizados.

O CSV aceita a coluna opcional `status`, também reconhecida como `order_status`. Os valores são `pending` (Pendente), `created` (Criado), `approved` (Aprovado), `invoiced` (Faturado), `processing` (Em preparação), `shipped` (Em transporte), `delivered` (Entregue), `canceled` (Cancelado), `unavailable` (Indisponível) e `unknown` (Não informado). O backend valida o valor por linha e o persiste. Quando ausente, usa `shipped` se houver despacho e `unknown` nos demais casos. Esse campo representa a situação logística informada pela fonte do pedido. O modelo calcula seu próprio resultado de risco a cada simulação.

A listagem e o detalhe `/api/v1/orders/:orderId` devolvem `status`, `estimated_delivery_at`, peso em gramas (`total_weight_g`), volume (`total_volume_cm3`) e distância (`distance_km`). Medidas e valores financeiros são números JSON ou `null`. A tela Pedidos exibe status e entrega prometida na tabela e nos detalhes. A seleção no Simulador Logístico carrega o detalhe completo antes de preencher o formulário, converte gramas para quilogramas e limpa campos ausentes. Os campos obrigatórios devem ser preenchidos para executar uma previsão.

A migration `20261109000000_add_order_status.cjs` acrescenta a coluna de status às instalações PostgreSQL existentes. O servidor executa migrations ao iniciar. O fallback JSON aceita registros antigos sem regravação em massa. O resumo em `/api/v1/orders/summary` conta pedidos operacionais distintos com previsões persistidas, incluindo o histórico JSON/JSONL.

Esta é a rota oficial da BE-02: `/orders` no enunciado corresponde ao recurso
versionado `/api/v1/orders` usado pelo Flutter. Os pedidos demonstrativos já
cadastrados e os registros Olist continuam sendo consultados nessa rota.

Cada pedido da listagem e de `GET /api/v1/orders/:orderId` inclui `status` e,
quando informada na importação, `estimated_delivery_at` (data prometida).
O Flutter exibe esses campos na tabela e no diálogo **Ver detalhes**.

| Status | Exibição | Significado |
| --- | --- | --- |
| `pending` | Pendente | Pedido registrado sem evidência de despacho |
| `shipped` | Em transporte | Pedido despachado, sem confirmação de entrega |
| `delivered` | Entregue | Entrega informada na origem dos dados |
| `canceled` | Cancelado | Cancelamento informado na origem dos dados |

`POST /api/v1/orders/import` aceita `status` opcional em cada pedido; sem ele,
usa `unknown` (ou `shipped` se houver informação de despacho no item).
Reimportar um pedido existente preserva seu status. Status inválido retorna
HTTP 422 com `INVALID_STATUS`, antes de gravar qualquer pedido do lote.

`POST /api/v1/orders/import-csv` aceita a coluna opcional `status`. Sem ela ou
com célula vazia, usa `shipped`, pois esse CSV exige `dispatched_at`. Valores
inválidos entram na relação de linhas com falha e não são persistidos.

Novos pedidos persistem o status tanto no PostgreSQL quanto no fallback JSON.
A migração `20250101000004_add_order_status.cjs`, executada na inicialização da API,
preenche pedidos antigos do PostgreSQL com `shipped` quando possuem despacho e
`unknown` nos demais casos. Registros JSON antigos sem status seguem a mesma
regra na leitura e salvam o valor ao serem reimportados. O vencimento do prazo
não é usado para deduzir uma entrega, um cancelamento ou o risco de atraso.
O status é operacional e não é enviado como feature ao modelo de previsão.

```bash
curl 'http://localhost:3001/api/v1/orders?source=operational&per_page=5'
curl 'http://localhost:3001/api/v1/orders/ID_DO_PEDIDO'
```

### Parâmetros de consulta

| Parâmetro | Tipo | Padrão | Máximo | Descrição |
| --- | --- | --- | --- | --- |
| `page` | inteiro | 1 | 9999 | Número da página |
| `per_page` | inteiro | 50 | 500 | Itens por página |
| `hub_id` | texto | — | — | Filtra por hub associado |
| `q` | texto | — | — | Busca texto contido no `order_id` |
| `source` | texto | — | — | Filtra pela origem, como `operational` ou `olist` |

### Exemplo de resposta

```json
{
  "data": [
    {
      "order_id": "order-001",
      "origin_zip_code": "01001000",
      "destination_zip_code": "20040002",
      "estimated_delivery_at": "2026-11-12T18:00:00",
      "status": "shipped",
      "total_weight_g": 500,
      "total_volume_cm3": 1200,
      "distance_km": 360,
      "hub_id": "hub-stable-id-1",
      "hub": {
        "id": "hub-stable-id-1",
        "code": "HUB-01",
        "name": "Hub São Paulo",
        "city": "São Paulo",
        "state": "SP"
      },
      "source": "operational",
      "created_at": "2026-11-01T12:00:00.000Z",
      "updated_at": "2026-11-01T12:00:00.000Z"
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
