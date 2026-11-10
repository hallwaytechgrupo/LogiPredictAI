# Cadastro de hubs

Para demonstrar FE-04 e BE-02, importe `back/data/exemplos_fe04_be02.csv` pela aba Pedidos. O arquivo contém cinco pedidos fictícios identificados pelo prefixo `DEMO-FE04-`, com datas, pesos e status logísticos informados. A tabela e os detalhes exibem entrega prometida e status. O Simulador Logístico busca o detalhe completo ao selecionar um pedido importado. [Contrato e status aceitos](../docs/api.md#listagem-de-pedidos).

`POST /predict` implementa o BE-03 com peso em gramas (`total_weight_g`), distância Haversine em quilômetros (`distance_km`) e prazo restante em dias de calendário (`remaining_days`). Retorna Baixo, Médio ou Alto a partir dos percentis de transporte de 53.327 pedidos reais da Olist. [Contrato, regras, fonte e reprodução](../docs/be-03-predict.md).

## BE-02 — contrato de listagem de pedidos

O recurso da atividade `GET /orders` está disponível como `GET /api/v1/orders`,
mantendo a rota versionada usada pela aplicação. A listagem e o detalhe retornam
o status operacional (`pending`, `created`, `approved`, `invoiced`, `processing`, `shipped`, `delivered`, `canceled`, `unavailable`, `unknown`) e a data
prometida `estimated_delivery_at`. A tela de pedidos mostra ambos na tabela e
no botão **Ver detalhes**.

Novas importações persistem o status em PostgreSQL ou JSON. A coluna `status`
é opcional no CSV; o padrão é `shipped` quando existe despacho, ou `unknown`
sem despacho. O importador JSON também aceita `status` por pedido e preserva
o status de pedidos já registrados. A migração de banco roda automaticamente
ao iniciar a API. [Contrato e compatibilidade com registros antigos](../docs/api.md#listagem-de-pedidos).

Após atualizar o código, reconstrua os serviços para aplicar a migração e a tela:

```bash
docker compose up -d --build api web
```

Os testes de status e listagem podem usar o fallback JSON sem acessar o banco
de desenvolvimento, a partir de `back/`:

```bash
DB_HOST=127.0.0.1 DB_PORT=1 node --test test/order_status.test.js test/orders_list_api.test.js
```

## Simulação automatizada do dataset Olist

O arquivo preparado para o simulador Flutter fica por padrão em `back/data/pedidos_logipredict.csv` (97.641 linhas de pedidos no dataset atual). Em execução local, a API procura `data/pedidos_logipredict.csv` relativo ao diretório de trabalho do backend. É possível mudar o arquivo com `OLIST_DATASET_FILE=data/meu_dataset_olist.csv`.

No Docker Compose, o arquivo do host é configurável pela variável `OLIST_DATASET_HOST_FILE` (padrão `./back/data/pedidos_logipredict.csv`) e montado como leitura apenas para a API. O backend expõe `GET /api/v1/datasets/olist`, que devolve o CSV preparado como `text/csv`; retorna 404 quando o arquivo configurado não existe e 422 se estiver vazio. Não há caminho absoluto de máquina embutido no aplicativo.

O botão **Executar simulação Olist** baixa esse CSV, valida seu schema e importa pedidos em blocos de no máximo 2.000 IDs, respeitando o limite `POST /api/v1/orders/import` e o limite de corpo JSON da API. A análise usa uma chamada sequencial ao endpoint de previsão individual por pedido; cada resposta real persiste no histórico por `order_id` e captura o `hub_id` vigente. Não há paralelismo de chamadas ao ML. Como o dataset contém dezenas de milhares de linhas e cada previsão é individual, a execução pode ser longa; o botão Cancelar interrompe novos pedidos e mantém as importações/previsões já concluídas.

Na importação Olist, o `default_hub_id` é uma associação explicitamente escolhida para demonstração. A API aplica esse hub a pedidos novos e pedidos existentes sem associação; mantém qualquer vínculo existente com outro hub e retorna `hub_preserved`. A importação é idempotente por `order_id`, então não duplica registros. Reexecutar a simulação não duplica os pedidos, mas solicita novas previsões e preserva seu histórico.

Os candidatos a hubs são importados pela tela **Gestão de Hubs** no aplicativo. Use o botão de upload para selecionar um CSV com as colunas `code`, `state`, `osm_id`, `latitude` e `longitude`, além de uma coluna de nome (`name` ou `name_ficticio`). A coluna de município pode ser `city` ou `city_osm`. O arquivo é lido pelo Flutter e enviado em lote à API; o backend não lê CSV do disco.

Na importação, candidatos novos são criados inativos e pendentes de validação. Registros existentes são identificados pelo `osm_id` ou código. Se os dados importados mudarem, o cadastro é atualizado e volta a ficar pendente/inativo; sem mudanças, seu estado de revisão é preservado.

Na tela **Gestão de Hubs**, selecione um ou mais candidatos pendentes e escolha **Adicionar selecionados** para aprová-los e ativá-los em lote. **Selecionar todos** marca os registros atualmente listados. Hubs sem cidade precisam ser corrigidos antes da aprovação. Para excluir em lote, marque os hubs e escolha **Excluir selecionados**. As operações são enviadas à API.

Na tela **Gestão de Hubs**, filtre pendentes, abra os detalhes da fonte, corrija município quando necessário e aprove ou rejeite o candidato. Aprovar ativa o hub. A API não permite ativar candidatos pendentes ou rejeitados.

## Simulação de risco de atraso no despacho

A tela de simulação envia pedidos para `POST /api/v1/predictions`, que encaminha o JSON sem transformação ao serviço FastAPI `/predict`. A unidade é o pedido; campos como `items_count`, `sellers_count`, preço, frete e peso representam agregados do pedido. A tela não calcula score nem prazo novo.

O contrato exige `purchase_at`, `dispatched_at`, `estimated_delivery_at`, `seller_state`, `customer_state`, `items_count`, `sellers_count`, `price` e `freight_value`. `distance_km`, `total_weight_g` e `total_volume_cm3` são opcionais no schema; as três são features reais do Random Forest, e atributos ausentes podem ser imputados pelo pipeline. O app omite volume se o usuário não o informar e mostra os avisos retornados pelo modelo. CEPs/cidade/coordenadas e número de hubs não são features: CEPs resolvem localização para as features de UF e distância.

Para resolver localizações, a API Node fornece `POST /api/v1/geolocation/route`. Configure `GEOLOCATION_FILE` para `olist_geolocation_dataset.csv`. No Docker Compose, o CSV é montado em `/app/geolocation/olist_geolocation_dataset.csv`; após atualizar o compose, recrie o serviço da API (`docker compose up --build -d api`). A consulta usa o prefixo de cinco dígitos do CEP, calcula medianas de latitude/longitude por prefixo e escolhe cidade/UF predominantes. CEPs sem correspondência falham explicitamente, sem coordenadas padrão.

A distância segue o pipeline de treinamento: fórmula Haversine entre as coordenadas medianas, raio terrestre de 6371.0088 km, em quilômetros. Para vários vendedores, a distância do pedido é a maior distância vendedor-destino, como na preparação dos dados Olist. A geolocalização é histórica e agregada por prefixo, portanto não representa o ponto exato do endereço. O score do artefato atual é não calibrado; a resposta inclui versão, limiar, decisão e avisos. A estimativa classifica risco em relação à data prometida e não identifica a causa nem prevê outra data de entrega.

## Associação de pedidos a hubs

O backend não tinha uma entidade nem persistência de pedidos. O fluxo de lote agora registra as chaves `order_id` dos pedidos importados em JSON, junto com o `hub_id` opcional. Em execução local, o arquivo é `data/orders.json` relativo ao backend; no Docker Compose, `ORDERS_FILE=/app/data/orders.json` persiste no volume de hubs. Pedidos antigos sem campo permanecem sem associação, e importar novamente uma linha sem seleção de hub preserva um vínculo explicitamente salvo. A seleção é manual por pedido; não há inferência por coordenadas.

`POST /api/v1/orders/import` recebe `{ "orders": [{ "order_id": "..." }] }` e registra pedidos importados sem atribuir hub. Opcionalmente aceita `default_hub_id` para a execução de demonstração Olist: atribui o hub validado somente quando o pedido é novo ou não tinha vínculo; uma associação existente diferente é preservada. Cada resultado inclui `imported`, `demo_hub_assigned` e `hub_preserved`. A rota aceita no máximo 2.000 IDs por chamada e reimporta `order_id` sem duplicar registros. `PATCH /api/v1/orders/{order_id}/hub` recebe `{ "hub_id": "<id estável de hub>" }` para associar ou `{ "hub_id": null }` para remover a associação. A rota exige que o pedido tenha sido importado e que o hub exista. `GET /api/v1/orders/{order_id}` retorna `order_id`, `hub_id` opcional, um resumo do hub e timestamps. A lista de pedidos continua sendo fornecida pelo CSV importado na tela de lote; a API persiste a chave e o vínculo, não uma cópia dos atributos do modelo. O campo de associação nunca é enviado ao serviço Python.

Hubs que estejam associados a pedidos não podem ser removidos pelas rotas de exclusão individual ou em lote até que os vínculos sejam limpos ou alterados.

## Histórico e agregação de previsões por hub

O Node mantém o histórico de inferência em `data/predictions.json` (legado, quando existente) e acrescenta previsões novas em `data/predictions.jsonl`, ou nos caminhos definidos por `PREDICTIONS_FILE` e `PREDICTIONS_JOURNAL_FILE`. No Docker Compose ambos ficam em `/app/data`, no volume persistente configurado. O journal JSONL evita reescrever todo o histórico a cada previsão, o que é necessário para execuções extensas. Registros guardam `prediction_id`, `order_id`, `hub_id` capturado antes da chamada ao ML (pode ser `null`), `delay_probability`, `predicted_late`, `threshold`, `model_version`, `source`, `synthetic`, `warnings` e `predicted_at` UTC. A resposta do modelo é mantida; o Node não produz score nem decisão.

Para registrar uma previsão, use `POST /api/v1/predictions?order_id=<id>` com o corpo original do contrato de inferência. O pedido precisa existir em `orders.json`; a API captura o vínculo no início da requisição e encaminha somente o corpo existente ao Python. Uma chamada sem `order_id` mantém a simulação individual atual e não é persistida. A resposta registrada mantém os campos do ML e acrescenta `prediction_id` e `persisted: true`. Falha ao salvar retorna HTTP 500 com `PREDICTION_PERSISTENCE_ERROR`, a resposta real dentro de `prediction` e `persisted: false`; previsões repetidas recebem IDs distintos e não sobrescrevem o histórico. Resposta de modelo sintética é marcada no histórico, mas não entra na agregação.

`GET /api/v1/analytics/hubs` aceita `start_date` e `end_date` (`YYYY-MM-DD`, inclusivas em UTC, comparadas com `predicted_at`) e `hub_id`. A API não chama o ML durante a consulta. Considera somente registros completos com `synthetic: false`, `hub_id` de hub atualmente aprovado e os campos de decisão/limiar/versão/data válidos. Registros sem hub, incompletos, sintéticos, ligados a candidatos/rejeitados ou associados a hubs removidos são excluídos. Hubs sem previsões elegíveis não aparecem; sem resultados, retorna `data: []` e `total: 0`.

Por hub, `predictions_count` conta previsões incluídas, `risk_count` conta `predicted_late: true` retornado pelo modelo e `risk_percentage` é essa contagem dividida pelo total, em percentual. Não se deriva a decisão comparando novamente o score ao limiar. `thresholds` e `model_versions` listam os valores observados; campos singulares ficam preenchidos somente se houver um único valor, e os flags de consistência explicitam divergências. `period_start`, `period_end` e `last_prediction_at` referem-se aos timestamps efetivamente incluídos.

Exemplo esquemático de uma linha agregada. Os números abaixo apenas ilustram tipos/formato e não são dados do ambiente; respostas reais são calculadas do histórico persistido:

```json
{
  "hub_id": "<id estável do hub>",
  "predictions_count": 12,
  "risk_count": 4,
  "risk_percentage": 33.33333333333333,
  "period_start": "<timestamp UTC da primeira previsão>",
  "period_end": "<timestamp UTC da última previsão>",
  "threshold": 0.37,
  "thresholds": [0.37],
  "thresholds_consistent": true,
  "model_version": "<versão retornada pelo modelo>",
  "model_versions": ["<versão retornada pelo modelo>"],
  "model_versions_consistent": true,
  "last_prediction_at": "<timestamp UTC>"
}
```

Esse agregado descreve decisões de previsões individuais agrupadas por associação manual; não é um modelo de risco geográfico próprio do hub. A persistência JSON faz gravação por arquivo temporário e serializa mutações dentro de uma instância Node, mas não fornece transações, bloqueio entre múltiplos processos nem as garantias de um banco de dados. Mantenha uma única instância gravadora ou migre o histórico para uma base transacional se a concorrência/volume crescer.
