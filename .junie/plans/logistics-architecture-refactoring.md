---
sessionId: session-261106-161332-13hk
---

# Requirements

## Overview & Goals

Transformar o LogiPredictAI de um sistema baseado em simulação Olist em lote para um sistema de gestão logística operacional com:
- Importação de pedidos operacionais via CSV independente do dataset Olist
- Associação geográfica automática aos hubs mais próximos
- Previsão de atrasos com ML preservando o contrato existente
- Simulador automático de despacho entre hubs (sem seleção manual)

## User Stories

1. **Como gestor logístico**, quero importar um CSV de pedidos operacionais para gerenciar pedidos reais, não dados de treinamento.
2. **Como gestor**, quero que cada pedido seja automaticamente associado ao hub mais próximo do CEP de destino.
3. **Como analista**, quero executar previsões de atraso nos pedidos importados e ver o histórico por pedido e hub.
4. **Como planejador**, quero simular despacho entre dois CEPs e ver automaticamente os hubs de origem/destino e a rota.
5. **Como administrador**, quero alterar manualmente o hub de um pedido quando necessário.

## Functional Requirements

### Importação de Pedidos
- Upload de CSV operacional pelo Flutter
- Validação de colunas obrigatórias (order_id, origin_zip_code, destination_zip_code, purchase_at, dispatched_at, estimated_delivery_at, seller_state, customer_state, items_count, sellers_count, price, freight_value)
- Deduplicação por order_id
- Importação em lotes (até 2000 por requisição)
- Persistência no PostgreSQL (com fallback JSON)
- Relatório: importados, ignorados, com falha
- Associação automática ao hub mais próximo do destino

### Associação de Hubs
- Geolocalização do CEP de destino via índice Olist existente
- Busca de hubs ativos e aprovados
- Cálculo Haversine para distância
- Seleção do hub mais próximo
- Preservação de associação manual em reimportação
- Registro quando não há hub disponível

### Previsão de Atraso
- Envio dos atributos compatíveis com o contrato ML (Shipment schema)
- Persistência da resposta real do modelo
- Registro de order_id e hub_id vigente
- Histórico de previsões por pedido e hub

### Simulador de Despacho
- Entrada: apenas CEP de despacho e CEP de chegada
- Seleção automática dos hubs mais próximos
- Cálculo de rota entre hubs via OpenRouteService
- Exibição de distâncias, hubs e rota no mapa
- Sem modificação de pedidos existentes

## Scope

### In Scope
- Backend Node.js: novos endpoints, modularização, camada de repositório
- Banco de dados: PostgreSQL/PostGIS com migrations
- Flutter: nova tela de importação, novo simulador de despacho
- Integração ML: preservar contrato existente
- Docker Compose: adicionar PostgreSQL
- Testes: cobertura dos novos fluxos

### Out of Scope
- Modificação do modelo ML ou do pipeline de treinamento
- Modificação do serviço Python (exceto integração)
- Remoção de funcionalidades úteis existentes
- Dados fictícios

# Technical Design

## Current Implementation

### Backend (back/src/app.js — 2288 linhas monolítico)
- Persistência em JSON: orders.json, hubs.json, predictions.jsonl
- Endpoints existentes:
  - `POST /api/v1/orders/import` — importa order_ids com hub_id opcional
  - `GET /api/v1/orders` — lista com paginação
  - `GET /api/v1/orders/:orderId` — detalhe
  - `PATCH /api/v1/orders/:orderId/hub` — altera hub
  - `POST /api/v1/predictions` — previsão individual
  - `POST /api/v1/predictions/batch` — previsão em lote (SSE)
  - `POST /api/v1/geolocation/route` — rota por CEPs
  - `GET/POST /api/v1/hubs/*` — CRUD de hubs
  - `GET /api/v1/analytics/*` — análises
- Geolocalização: índice carregado de `olist_geolocation_dataset.csv` (lazy loading)
- Haversine: função `haversineKm()` para distância em linha reta

### ML Service (back/ml/logipredict/)
- Schema `Shipment` (Pydantic): purchase_at, dispatched_at, estimated_delivery_at, seller_state, customer_state, distance_km, total_weight_g, total_volume_cm3, items_count, sellers_count, price, freight_value
- Features derivadas: dispatch_lead_days, remaining_days, purchase_month, dispatch_weekday
- Endpoint `POST /predict` retorna: model_version, source, synthetic, delay_probability, threshold, predicted_late, warnings

### Flutter (flutter_app/lib/)
- `shipment_csv_service.dart` — parse CSV com colunas ML
- `orders_api.dart` — importação, listagem, alteração de hub
- `logipredict_api.dart` — previsão e geolocalização
- `dispatch_simulation.dart` — payload ML
- `dashboard_simulator_screen.dart` — simulador individual
- `orders_management_screen.dart` — listagem de pedidos

### Docker Compose
- 3 serviços: ml (Python), api (Node.js), web (Flutter/Nginx)
- Sem PostgreSQL

## Key Decisions

1. **Migração gradual para PostgreSQL**: Adicionar PostgreSQL como camada primária para novos dados, mantendo JSON como fallback. Usar Knex.js para migrations.
2. **CSV completo**: Incluir todos os campos do Shipment do ML + campos operacionais (CEPs). Validação estrita no backend.
3. **OpenRouteService**: Roteamento rodoviário gratuito para o simulador de despacho.
4. **Modularização progressiva**: Extrair rotas para arquivos separados, manter app.js como entrada.
5. **Substituir simulação Olist**: Remover tela de simulação Olist, substituir por importação de CSV operacional.

## Proposed Changes

### 1. PostgreSQL/PostGIS
- Adicionar serviço PostgreSQL ao docker-compose.yml
- Criar migrations com Knex.js:
  - `orders` table: order_id, origin_zip_code, destination_zip_code, purchase_at, dispatched_at, estimated_delivery_at, seller_state, customer_state, items_count, sellers_count, price, freight_value, distance_km, total_weight_g, total_volume_cm3, hub_id, source, created_at, updated_at
  - `predictions` table: prediction_id, order_id, hub_id, delay_probability, predicted_late, threshold, model_version, source, synthetic, warnings, predicted_at
  - `dispatch_simulations` table (opcional): simulation_id, origin_cep, destination_cep, origin_hub_id, destination_hub_id, distances, route_geometry, created_at
- Índices: order_id, hub_id, geográficos (PostGIS)
- Integridade referencial: FK hub_id → hubs

### 2. Camada de Repositório
- `back/src/db/repositories/orders.js` — abstrai JSON vs PostgreSQL
- `back/src/db/repositories/predictions.js`
- `back/src/db/repositories/hubs.js`
- `back/src/db/knex.js` — configuração do Knex
- `back/src/db/migrations/` — migrations reversíveis

### 3. Novos Endpoints
- `POST /api/v1/orders/import` — adaptado para aceitar CSV completo com validação
- `POST /api/v1/geolocation/nearest-hub` — hub mais próximo de CEP/coordenada
- `POST /api/v1/dispatch/simulate` — simulação automática de despacho
- `POST /api/v1/predictions?order_id=` — previsão com persistência (já existe, adaptar)

### 4. Flutter
- Nova tela de importação de pedidos (substitui simulação Olist)
- Nova tela de simulador de despacho (independente)
- Adaptar `shipment_csv_service.dart` para novo contrato CSV
- Adaptar `orders_api.dart` para novos endpoints
- Novo serviço `dispatch_api.dart` para simulação

### 5. Docker Compose
- Adicionar serviço PostgreSQL/PostGIS
- Volumes persistentes
- Variáveis de ambiente

# Testing

## Validation Approach

Testes unitários e de integração no backend (Jest), validação manual no Flutter.

## Key Scenarios

1. **Importação CSV válido**: CSV com todas as colunas obrigatórias → pedidos persistidos, hubs associados
2. **CSV com colunas ausentes**: Erro 422 com lista de colunas faltantes
3. **Pedidos duplicados**: Deduplicação por order_id, relatório de ignorados
4. **Associação automática**: Pedido com CEP válido → hub mais próximo associado
5. **CEP sem geolocalização**: Pedido persistido sem hub, motivo registrado
6. **Nenhum hub ativo**: Pedido persistido sem hub, erro de negócio
7. **Preservação manual**: Reimportação não substitui hub manual
8. **Simulador de despacho**: Dois CEPs → hubs automáticos + rota
9. **Mesmo hub**: Origem e destino no mesmo hub → mensagem clara
10. **OpenRouteService indisponível**: Distância Haversine + aviso
11. **Previsão com persistência**: Previsão registrada com hub_id vigente
12. **Histórico de previsões**: Múltiplas previsões por pedido e hub

## Test Changes

- `back/test/orders_import_csv.test.js` — importação de CSV operacional
- `back/test/geolocation_nearest_hub.test.js` — associação automática
- `back/test/dispatch_simulation.test.js` — simulador de despacho
- `back/test/prediction_persistence.test.js` — persistência de previsões
- Adaptar testes existentes para novo contrato

# Delivery Steps

### ✓ Step 1: 1. PostgreSQL setup e migrations
Adicionar PostgreSQL/PostGIS ao Docker Compose e criar migrations para as tabelas de pedidos, previsões e simulações.
- Adicionar serviço `postgres` ao docker-compose.yml com PostGIS
- Criar `back/src/db/knex.js` com configuração do Knex
- Criar migration para tabela `orders` com todos os campos do CSV operacional + hub_id
- Criar migration para tabela `predictions` com histórico de previsões
- Criar migration opcional para `dispatch_simulations`
- Adicionar índices: order_id, hub_id, geográficos
- Executar migrations e verificar schema
- Adicionar variáveis de ambiente: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD

### ✓ Step 2: 2. Camada de repositório para pedidos e previsões
Criar camada de repositório que abstrai a persistência (JSON vs PostgreSQL).
- Criar `back/src/db/repositories/orders.js` com métodos: create, findById, list, updateHub, associateHub
- Criar `back/src/db/repositories/predictions.js` com métodos: create, findByOrderId, list
- Criar `back/src/db/repositories/hubs.js` com métodos: listActive, findById, nearest
- Implementar fallback para JSON se PostgreSQL indisponível
- Adaptar `app.js` para usar repositórios nos endpoints existentes
- Garantir que os endpoints existentes continuem funcionando

### ✓ Step 3: 3. Novo endpoint de importação de CSV operacional
Adaptar POST /api/v1/orders/import para aceitar CSV completo com validação.
- Validar colunas obrigatórias: order_id, origin_zip_code, destination_zip_code, purchase_at, dispatched_at, estimated_delivery_at, seller_state, customer_state, items_count, sellers_count, price, freight_value
- Validar tipos e valores (datas, números, UFs)
- Deduplicar por order_id
- Persistir no PostgreSQL via repositório
- Associar automaticamente ao hub mais próximo do destination_zip_code
- Retornar relatório: importados, ignorados, com falha
- Extrair para `back/src/routes/orders.js` (modularização)
- Criar teste: `back/test/orders_import_csv.test.js`

### ✓ Step 4: 4. Endpoint de hub mais próximo e associação automática
Criar POST /api/v1/geolocation/nearest-hub para identificar o hub mais próximo.
- Receber CEP ou coordenadas (lat/lng)
- Resolver CEP para coordenadas via índice Olist
- Buscar hubs ativos e aprovados com coordenadas válidas
- Calcular distância Haversine para cada hub
- Retornar o hub mais próximo (empate: menor hub_id)
- Retornar erro se não houver hubs elegíveis
- Extrair para `back/src/routes/geolocation.js`
- Criar teste: `back/test/geolocation_nearest_hub.test.js`

### ✓ Step 5: 5. Simulador automático de despacho
Criar POST /api/v1/dispatch/simulate para simulação automática.
- Receber origin_cep e destination_cep
- Resolver ambos os CEPs para coordenadas
- Selecionar automaticamente o hub mais próximo de cada CEP
- Calcular distância Haversine entre os hubs
- Integrar com OpenRouteService para rota rodoviária
- Retornar: hubs de origem/destino, distâncias, rota, geometria
- Tratar: mesmo hub, sem hubs elegíveis, serviço indisponível
- Extrair para `back/src/routes/dispatch.js`
- Criar teste: `back/test/dispatch_simulation.test.js`

### ✓ Step 6: 6. Flutter - Nova tela de importação de pedidos
Substituir a tela de simulação Olist por importação de CSV operacional.
- Adaptar `shipment_csv_service.dart` para novo contrato CSV (com CEPs)
- Criar nova tela de importação com upload de CSV
- Mostrar progresso da importação
- Exibir relatório: importados, ignorados, com falha
- Exibir hub atribuído automaticamente a cada pedido
- Exibir quando um pedido não encontrou hub
- Permitir alterar manualmente o hub de um pedido
- Adaptar `orders_api.dart` para novo endpoint de importação
- ✓ Removido `dashboard_batch_screen.dart` (simulação Olist)
- Atualizar `dashboard_screen.dart` para usar nova tela

### ✓ Step 7: 7. Flutter - Nova tela de simulador de despacho
Criar tela independente de simulador de despacho.
- Campos: CEP de despacho e CEP de chegada
- Botão para calcular despacho
- Indicador de processamento
- Exibir: hubs selecionados automaticamente, distâncias, rota
- Mapa com origem, destino e hubs
- Sem seletores manuais de hub
- Criar `dispatch_api.dart` para comunicação com backend
- Integrar com `google_maps_flutter` ou `flutter_map` para exibição
- Tratar erros: CEP inválido, sem hubs, serviço indisponível

### ✓ Step 8: 8. Previsão de atraso com persistência
Adaptar o fluxo de previsão para persistir no PostgreSQL.
- Adaptar `POST /api/v1/predictions?order_id=` para usar repositório
- Persistir previsão com hub_id vigente no momento
- Manter histórico por pedido e hub
- Garantir que o contrato ML não seja modificado
- Adaptar Flutter para enviar previsão após importação
- Criar teste: `back/test/prediction_persistence.test.js`

### ✓ Step 9: 9. Docker Compose e configuração final
Atualizar Docker Compose e configurações para o ambiente completo.
- Adicionar serviço PostgreSQL/PostGIS ao docker-compose.yml
- Configurar volumes persistentes para dados
- Atualizar variáveis de ambiente da API
- Garantir comunicação entre containers
- Atualizar Flutter Web para usar proxy Nginx em /api
- Verificar que todos os serviços iniciam corretamente
- Testar integração completa: Flutter → API → PostgreSQL → ML

### ✓ Step 10: 10. Testes, documentação e validação final
Criar e executar testes, atualizar documentação e validar o sistema completo.
- Executar todos os testes do backend
- Validar fluxos end-to-end no Flutter
- Atualizar README principal, back/README.md, README do Flutter
- Documentar novos endpoints
- Exemplo de CSV operacional
- Variáveis de ambiente
- Instruções de execução local e Docker
- Remover referências à importação Olist como fluxo operacional
- Validar critérios de aceite: importação de CSV independente + associação automática + simulador de despacho

### ✓ Step 11: Unificação das telas de Importação e Pedidos
Unificar "Importação de Pedidos" e "Pedidos" em uma única tela "Pedidos".
- Criado `flutter_app/lib/screens/orders_screen.dart` — tela unificada com resumo, importação CSV, listagem e detalhes
- Removida a aba "Pedidos" independente do dashboard (de 6 para 5 abas)
- Renomeada a aba "Importação de Pedidos" para "Pedidos"
- Adicionado filtro `source` ao backend (`GET /api/v1/orders?source=operational`)
- Adicionado endpoint `GET /api/v1/orders/summary` com indicadores operacionais
- Corrigido erro de leitura de CSV no Flutter Web (uso de `FilePicker.pickFiles()` + `bytes`)
- Separados pedidos operacionais dos registros históricos Olist via `source` filter
- Adicionado modal de detalhes do pedido e diálogo de alteração de hub
- Atualizado `orders_api.dart` com método `summary()` e parâmetro `source`

### ✓ Step 12: Seleção de pedidos importados no Simulador Logístico
Adicionar opção de selecionar pedido já importado no Simulador Logístico para auto-preenchimento.
- Adicionado toggle "Utilizar pedido importado" no formulário do simulador
- Campo de pesquisa por order_id com consulta à API `GET /api/v1/orders?q=`
- Resultados exibidos com ID, CEPs e hub associado
- Ao selecionar, todos os campos do formulário são preenchidos automaticamente
- Pedidos sem hub mostram opção "Associar agora" via `POST /api/v1/geolocation/nearest-hub`
- Previsão com `order_id` persiste o resultado no PostgreSQL
- Modo manual preservado sem alterações
- Método `nearestHub()` adicionado ao `DispatchApi`
- 117/117 testes de regressão passaram

### ✓ Step 13: Correção da associação automática de hubs por CEP
Corrigir o erro "Nenhum hub encontrado para o CEP de destino" ao clicar em "Associar agora".
- **Causa raiz**: Flutter lia `response['data']` em vez de `response['data']['hub']` em `_associateOrderHub()`
- **Causa secundária**: Repositório `hubs.js` não encontrava o arquivo JSON (caminho `data/hubs.json` em vez de `data/hubs/hubs.json`)
- Corrigido `dashboard_screen.dart`: leitura correta de `response['data']['hub']`, diálogo de carregamento, mensagens de erro específicas
- Corrigido `hubs.js`: caminho padrão `data/hubs/hubs.json` para o fallback JSON
- Corrigido `routes/geolocation.js`: caminho do fallback JSON e campos `geolocation_method` + `association_status`
- Corrigido `routes/orders.js`: merge dos hubs JSON com os do repositório para hub enrichment
- Criado `test/geolocation_cep_normalization.test.js` com 15 testes de normalização de CEP
- 132/132 testes de regressão passaram
- Pedido TESTE-0002 associado com sucesso a HUB-PR-038 (77.39 km)

### ✓ Step 14: Sincronização de associação de hubs entre Simulador e Pedidos
Corrigir que ao associar hub no Simulador, a aba Pedidos não refletia a mudança.
- **Causa raiz**: `OrdersScreen` era `const` no `IndexedStack`, carregando dados apenas em `initState()`
- Adicionado `ValueNotifier<int>` no Dashboard como mecanismo de refresh compartilhado
- `OrdersScreen` agora aceita `refreshTrigger` e recarrega `_summary` + `_orders` ao receber sinal
- Dashboard incrementa o trigger ao trocar para a aba Pedidos e após associação de hub no Simulador
- Criado `test/hub_association_sync.test.js` com 8 testes de sincronização
- 140/140 testes de regressão passaram

### ✓ Step 15: Correção de desempenho do Flutter Web — congelamento ao usar Ctrl + scroll
Corrigir o congelamento completo da aplicação no Chrome ao alterar o zoom do navegador.
- **Causa raiz**: `_buildMapPage()` e `_buildSimulator()` eram chamados no `build()` do Dashboard, recriando os dois FlutterMap a cada `setState`. Ctrl+scroll disparava MediaQuery changes → rebuilds em cascata → hit testing exponencial nos widgets de mapa reconstruídos.
- Criado `flutter_app/lib/widgets/logistics_heat_map.dart` — `LogisticsHeatMap` StatefulWidget independente com `MapController` e `LayerHitNotifier` próprios, preservando estado entre reconstruções do Dashboard
- Simplificado `dashboard_map_screen.dart` — delega para `LogisticsHeatMap` via callbacks
- Removido `MapController` e `LayerHitNotifier` de `dashboard_screen.dart` (agora pertencem ao widget)
- Removido `addPostFrameCallback` com `_mapController.move/fitCamera` em `_loadMapHubs()` (o widget gerencia a câmera)
- 142/142 testes de regressão passaram