# Sprint 1 — Ciência de dados, IA e estrutura inicial

**Objetivo:** demonstrar a mineração da Olist, o tratamento dos dados, o treinamento Random Forest e uma previsão acessível por HTTP. Review informada pela equipe para **20/10/2026**; aceite a confirmar na apresentação. A interface Flutter fica para uma fase posterior.

## Entregas e evidências

| Item | Evidência na branch back | Situação técnica |
| --- | --- | --- |
| Obtenção da Olist | `scripts/download_olist.py`, `data/README.md` | Implementado |
| Limpeza e integração | `ml/logipredict/prepare.py`, relatório de qualidade | Implementado |
| Engenharia de atributos | `ml/logipredict/schema.py`, dicionário de dados | Implementado |
| Treino Random Forest | `ml/logipredict/train.py`, artefato local | Implementado |
| Avaliação temporal | `reports/olist/`, baseline e gráficos | Executada na base real |
| Serviço de inferência | `ml/logipredict/service.py`, OpenAPI em `/docs` | Implementado |
| Estrutura da API | `api/src/`, exemplos HTTP | Implementado |
| Testes e integração | Testes Python, Node e `scripts/smoke_test.py` | Ver documentação de validação |
| Documentação acadêmica | README, backlog, arquitetura e protocolo | Preparada para revisão |

"Implementado" descreve a entrega técnica; o aceite acadêmico e o encerramento da sprint dependem da equipe e do professor.

## Roteiro de apresentação — aproximadamente 8 minutos

1. **Problema (1 min):** atrasos prejudicam planejamento e experiência de compra. A entrega desta sprint estima risco por pedido no despacho.
2. **Dados (2 min):** mostrar seis tabelas Olist, junções, quantidade de pedidos mantidos e dados ausentes. Explicar a agregação antes do merge.
3. **Modelo (2 min):** justificar Random Forest, mostrar features, cortes temporais e a comparação com baseline. Explicar por que acurácia isolada não basta.
4. **Demonstração (2 min):** consultar `/ready`, enviar `prediction.json`, mostrar validação com UF inválida e consultar histórico por UF.
5. **Limites e próximos passos (1 min):** dados antigos, ausência de transportadora, scores não calibrados, autenticação e persistência na próxima etapa; Flutter depois.

## Como demonstrar sem refazer o treinamento

Com o artefato `models/olist` já gerado, iniciar os dois serviços conforme o README e executar `scripts/smoke_test.py`. Abrir `reports/olist/README.md` para exibir métricas e gráficos. Os modelos binários são locais e não acompanham o Git; numa nova máquina é necessário treinar novamente.

Se precisar usar a demonstração sintética, anunciar explicitamente que ela serve para comprovar integração e não desempenho real. Não misturar gráficos sintéticos com resultados Olist.

## Pendências para a próxima review

Refinar regras de negócio, responsabilidades e calendário; definir autenticação e persistência; avaliar custo dos erros e calibração; planejar integração Flutter e o futuro mapa. Não atribuir responsáveis individuais nem datas retroativas sem acordo da equipe.
