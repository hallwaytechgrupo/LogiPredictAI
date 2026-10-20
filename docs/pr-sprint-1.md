## Problema e comportamento entregue

O projeto precisava transformar a proposta de previsão de atrasos em uma primeira entrega executável para a Sprint 1. Foi implementado o tratamento da base Olist, a engenharia de atributos e o treinamento de um classificador Random Forest para estimar o risco de atraso de um pedido no momento do despacho.

A entrega inclui uma API Node.js integrada ao serviço Python, permitindo enviar dados do pedido e receber score de atraso, classificação, limiar e versão do modelo. Também disponibiliza agregados históricos por UF, documentação, exemplos de requisição e relatórios de avaliação. A interface Flutter, a autenticação e a persistência de pedidos permanecem para as próximas etapas.

## Validação

Validação local registrada em 20/10/2026, com Python 3.13.4 e Node.js 22.14.0. Na raiz do projeto, foram executados:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check ml scripts
.\.venv\Scripts\python.exe -m pip check
npm.cmd test --prefix api
npm.cmd run check --prefix api
.\.venv\Scripts\python.exe scripts/run_local.py --smoke
```

Resultados: 18 testes Python e 6 testes Node.js aprovados, análise estática e sintaxe aprovadas, dependências consistentes e integração Node.js → Python → modelo real aprovada. A execução remota da CI deve ser verificada no GitHub Actions; não está sendo presumida a partir do resultado local.

O treinamento principal utilizou dados reais da Olist v2, de 2016–2018: 99.441 pedidos de entrada e 96.281 elegíveis. A separação foi cronológica por despacho, aproximadamente 60%/20%/20%, com cortes em 06/03/2018 às 20:17:57 e 29/05/2018 às 12:04:00. Pedidos com entrega ainda desconhecida no corte seguinte foram removidos dos períodos de desenvolvimento. A divisão final contém 54.761 registros de treino, 17.445 de validação e 19.258 de teste, com 4.817 removidos nos cortes.

No teste, com limiar 0,39 escolhido somente na validação: precisão de 12,84%, recall de 75,85%, F1 de 0,2196, Average Precision de 0,3692 e ROC AUC de 0,8667. Foram detectados 534 dos 704 atrasos, com 3.625 falsos alertas. O score ainda não tem calibração validada, e os resultados não demonstram prontidão operacional.

Os dados sintéticos são usados separadamente para testes e demonstração da integração, sempre identificados como `synthetic: true`; eles não sustentam as métricas Olist acima. Limitações adicionais: base histórica, ausência de identificação de transportadora e classificação por pedido, sem individualização dos pacotes. Há um aviso de depreciação no cliente de testes Starlette/AnyIO, sem falha funcional.

## Referência

Backlog: **US01, US02, US03, US04, US05 e US06**, relacionados à integração dos dados, features, treinamento, avaliação, contrato HTTP e histórico por UF. Requisitos não funcionais: **RNF01 a RNF05**.

Evidências: `docs/backlog.md`, `docs/validation.md`, `docs/sprints/sprint-1.md` e `reports/olist/`.

Não foi vinculada uma issue específica; adicionar o número somente se houver uma issue correspondente no GitHub.
