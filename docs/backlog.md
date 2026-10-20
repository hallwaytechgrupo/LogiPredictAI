# Backlog inicial do produto

Proposta para refinamento e aceite pela equipe. Prioridade e pontos são estimativas, não um registro de aprovação ou de esforço realizado.

| ID | História de usuário | Sprint proposta | Prioridade | Pontos | Critério de aceite |
| --- | --- | --- | --- | ---: | --- |
| US01 | Como analista, quero integrar os CSVs Olist para analisar pedidos sem duplicação | 1 | Alta | 5 | Uma linha por pedido e relatório de qualidade |
| US02 | Como cientista de dados, quero definir features disponíveis no despacho para evitar vazamento | 1 | Alta | 5 | Dicionário e transformação compartilhada |
| US03 | Como gestor, quero identificar risco de atraso para priorizar acompanhamento | 1 | Alta | 8 | Random Forest serializado, avaliado temporalmente e comparado a baseline |
| US04 | Como avaliador, quero consultar métricas e gráficos para entender os limites do modelo | 1 | Alta | 3 | F1, precisão, recall, AP, matriz e protocolo reproduzível |
| US05 | Como desenvolvedor, quero um contrato HTTP para integrar a futura interface | 1 | Média | 5 | API Node → Python, validação e exemplos executáveis |
| US06 | Como gestor, quero consultar gargalos históricos por UF para explorar padrões | 1 | Média | 3 | Agregados com contagem, taxa, período e fonte |
| US07 | Como usuário, quero autenticar e acessar somente os dados autorizados | 2 | Alta | A estimar | Fluxo de autenticação e autorização definido e testado |
| US08 | Como gestor, quero registrar pedidos e histórico de previsões para acompanhar decisões | 2 | Alta | A estimar | Modelo de persistência e regras aprovadas |
| US09 | Como gestor, quero definir ações por faixa de risco conforme o custo dos erros | 2 | Alta | A estimar | Limiar e regras operacionais validados com a equipe |
| US10 | Como usuário, quero visualizar gargalos em mapa e gráficos no Flutter | 3 | Média | A estimar | Interface Web/Mobile integrada à API |
| US11 | Como analista, quero comparar modelos e calibrar scores para avaliar a generalização | 2–3 | Alta | A estimar | Experimentos temporais sem ajuste no teste reservado |

## Requisitos não funcionais

| ID | Requisito | Evidência esperada |
| --- | --- | --- |
| RNF01 | Reproduzir o treinamento | Dependências diretas fixadas, seed, hash da base e parâmetros |
| RNF02 | Evitar informações futuras no treino | Features permitidas e teste dos cortes temporais |
| RNF03 | Tratar falhas de integração | HTTP 422, 503, 504 e testes de API |
| RNF04 | Permitir evolução independente dos módulos | Serviço Python e API Node separados |
| RNF05 | Documentar dados e limitações | Fonte, limpeza, unidade pedido e ausência de transportadora |

## Regras iniciais implementadas

- RN01: atraso significa entrega em data posterior à data prometida.
- RN02: previsão é feita no momento do despacho e por pedido.
- RN03: sem modelo disponível, retornar HTTP 503.
- RN04: dados inválidos retornam HTTP 422; não gerar previsão parcial.
- RN05: modelos sintéticos sempre informam `synthetic: true`.
- RN06: os agregados históricos por UF não representam previsões futuras.

As regras de cadastro, permissões, alertas, persistência e tratamento operacional ficam para a segunda review.
