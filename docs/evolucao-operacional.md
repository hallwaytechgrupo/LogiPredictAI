# Evolução da arquitetura operacional

O módulo operacional reúne importação de pedidos, associação a hubs, previsão
de atraso e simulação de despacho. Os pedidos importados são independentes da
base histórica Olist usada no treinamento dos modelos.

## Organização dos módulos

| Camada | Componentes | Responsabilidade |
| --- | --- | --- |
| API | `back/src/routes/orders.js` | Validação, importação e consulta de pedidos |
| Geolocalização | `back/src/routes/geolocation.js` | Resolução de CEP e identificação do hub mais próximo |
| Despacho | `back/src/routes/dispatch.js` | Associação de origem/destino a hubs e cálculo de rota |
| Persistência | `back/src/db/repositories/` | Acesso a pedidos, hubs e previsões em PostgreSQL ou JSON |
| Banco | `back/src/db/migrations/` | Versionamento da estrutura das tabelas |
| Interface | `flutter_app/lib/screens/orders_screen.dart` | Importação, resumo, consulta e detalhes dos pedidos |
| Inferência | `back/ml/logipredict/` | Validação dos atributos e execução dos modelos treinados |

## Importação de pedidos

O CSV operacional contém identificador, CEPs, datas, UFs, quantidades e valores
compatíveis com o contrato de previsão. A API verifica colunas obrigatórias,
tipos e cronologia antes de persistir cada registro. O relatório da importação
separa pedidos importados, duplicados ignorados e registros com falha.

A associação automática usa as coordenadas do CEP de destino e a distância
Haversine até os hubs elegíveis. Pedidos sem geolocalização ou sem hub disponível
continuam identificados na consulta. Uma associação manual existente é mantida
na reimportação do mesmo pedido.

## Persistência e histórico

Os repositórios concentram o acesso ao PostgreSQL e ao fallback JSON. As
migrations descrevem as mudanças de estrutura do banco. Cada previsão
operacional registra o pedido, o hub vigente, a versão do modelo, o score,
o limiar e a data da análise, permitindo consultar o histórico de resultados.

O histórico operacional de previsões é diferente do histórico de entregas
utilizado como atributo pelo classificador: o primeiro registra análises
executadas; o segundo reúne entregas concluídas antes da previsão.

## Simulação de despacho

Os CEPs de origem e destino determinam os hubs mais próximos. O simulador
consulta o serviço de rotas para exibir o trajeto rodoviário. Quando esse
serviço está indisponível, a distância em linha reta fica identificada como
aproximação. Uma simulação não modifica os dados dos pedidos importados.

## Interface e sincronização

A tela **Pedidos** reúne seleção do CSV, relatório de importação, indicadores,
busca, listagem, detalhes e alteração de hub. O Simulador Logístico pode carregar
um pedido importado para preencher os campos. Alterações na associação de hub
disparam a atualização da lista de pedidos.

No Flutter Web, o conteúdo do arquivo selecionado é obtido pelos bytes
disponibilizados pelo navegador. A leitura não depende de um caminho de arquivo
local acessível ao aplicativo Web.

## Mapa e planejamento de entregas

O mapa possui uma vista de histórico regional e outra de planejamento de uma
compra futura. A simulação futura recebe suas próprias entradas e utiliza o
modelo 564 + filtro contextual, sem exigir um pedido importado. Apenas o mapa
visível permanece montado, com zoom e arraste controlados pelo Leaflet.

O cache dos CSVs e agregados reduz releituras na consulta regional. A busca de
CEP usa um catálogo próprio e não inicializa o modelo. Os detalhes de uso estão
em [Mapa e demonstração](mapa-e-demonstracao.md).

## Verificação dos fluxos

Os testes cobrem validação de CSV, deduplicação, associação geográfica,
persistência de previsões, sincronização de telas, contrato da simulação futura
e tratamento de erros. Os resultados executados e os limites da homologação
estão registrados em [Validação da entrega](validation.md).
