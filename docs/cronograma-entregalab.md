# Cronograma e cartões para o EntregaLab

**Sprint 1: review em 20/10/2026, conforme informado pela equipe.** Sprints 2 e 3 ainda não têm datas oficiais. Abaixo está uma proposta de três semanas por sprint futura, com semanas relativas ao início que a equipe definir. Não representa calendário aprovado nem tarefas criadas no EntregaLab.

Os pontos são estimativas iniciais para refinamento, sem conversão automática em horas. Os responsáveis abaixo são frentes sugeridas; não são atribuições individuais. PO prioriza e valida o valor; SM acompanha andamento e impedimentos. Desenvolvedores devem assumir os cartões em conjunto com a equipe.

## Visão geral

| Sprint | Período | Objetivo | Evidência principal |
| --- | --- | --- | --- |
| 1 | Review em 20/10/2026 | Provar o fluxo dados → modelo → API | Relatório Olist e previsão HTTP funcionando |
| 2 | 3 semanas propostas; datas a definir | Refinar IA e consolidar regras e back-end | Experimentos documentados, autenticação, persistência e API testadas |
| 3 | 3 semanas propostas; após Sprint 2 | Entregar a experiência Flutter e validar a solução integrada | Aplicação Web/Mobile, mapa histórico, teste de usuário e demonstração final |

Se o calendário acadêmico for menor, priorizar um fluxo completo de previsão e histórico; negociar a redução do escopo antes de prometer todas as telas e experimentos.

## Sprint 1 — entrega técnica e review de hoje

Não distribuir artificialmente a implementação por datas passadas. Registrar o que está implementado, anexar evidências e solicitar o aceite na review.

| ID | Título do cartão | História | Frente sugerida | Pontos | Critério de aceite | Situação |
| --- | --- | --- | --- | ---: | --- | --- |
| S1-01 | Integrar e limpar a base Olist | US01 | Dados | 5 | Seis tabelas integradas em uma linha por pedido, com relatório de qualidade | Implementado; aceite pendente |
| S1-02 | Definir atributos disponíveis no despacho | US02 | Dados/IA | 5 | Features documentadas e transformação igual no treino e na inferência | Implementado; aceite pendente |
| S1-03 | Treinar Random Forest e baseline | US03 | IA | 8 | Artefato local, parâmetros, seed e divisão temporal registrados | Implementado; aceite pendente |
| S1-04 | Gerar métricas e gráficos de avaliação | US04 | IA/Qualidade | 3 | Relatório real com falsos alertas, recall, precisão, F1, AP e limitações | Implementado; aceite pendente |
| S1-05 | Integrar API Node.js ao serviço Python | US05 | Back-end | 5 | Previsão por HTTP, validação e erros de dependência testados | Implementado; aceite pendente |
| S1-06 | Expor histórico de atrasos por UF | US06 | Dados/Back-end | 3 | Contagem, taxa, período e origem identificados como histórico observado | Implementado; aceite pendente |
| S1-07 | Apresentar a entrega e registrar feedback | US01–US06 | Equipe/PO/SM | A estimar | Demonstração, evidências anexadas e decisões da review registradas | A realizar/confirmar |

Evidências: `docs/validation.md`, `reports/olist/`, `examples/prediction.json`, `docs/api.md` e o texto em `docs/pr-sprint-1.md`.

### Ordem sugerida para hoje

1. Executar a integração e conferir o exemplo de previsão.
2. Abrir o relatório e ensaiar a explicação de precisão e recall.
3. Anexar o PR, os gráficos e as evidências de teste ao EntregaLab.
4. Demonstrar o fluxo e as limitações; pedir aceite dos itens implementados.
5. Registrar feedback e repriorizar a Sprint 2. O status de aceite depende da review.

## Sprint 2 — IA, regras de negócio e back-end

### Semana 1: decisões e fundação

| ID | Título | História | Frente sugerida | Pontos | Dependência | Critério de aceite |
| --- | --- | --- | --- | ---: | --- | --- |
| S2-01 | Definir regras operacionais e critérios de alerta | US09 | PO/Back-end/IA | 3 | Review 1 | Campos obrigatórios, permissões, custos dos erros e capacidade de acompanhar alertas documentados |
| S2-02 | Modelar persistência de usuários, pedidos e previsões | US08 | Back-end | 5 | S2-01 | Modelo de dados, migrações, vínculos com usuário e versão do modelo, sem armazenar credenciais em texto |
| S2-03 | Criar protocolo temporal de experimentos | US11 | IA | 5 | S2-01 | Teste externo fora da seleção; janelas e remoção de resultados futuros verificadas; configuração e código identificados |
| S2-04 | Prototipar os fluxos da interface Flutter | US10 | Interface/PO | 3 | S2-01 | Fluxos de acesso, formulário, resultado, histórico e mapa revisados com o contrato da API |

### Semana 2: implementação e experimentos

| ID | Título | História | Frente sugerida | Pontos | Dependência | Critério de aceite |
| --- | --- | --- | --- | ---: | --- | --- |
| S2-05 | Implementar autenticação e autorização | US07 | Back-end | 8 | S2-01, S2-02 | Sessões/tokens definidos; rotas protegidas; acesso a dados de outro usuário rejeitado |
| S2-06 | Persistir pedidos e histórico de previsões | US08 | Back-end | 8 | S2-02, S2-05 | Cadastro/consulta com autorização, filtros básicos e versão do modelo associada à previsão |
| S2-07 | Comparar configurações e analisar erros | US11 | IA | 8 | S2-03 | Tabela de candidatos em validação temporal, comparação com a referência e análise de falsos alertas sem selecionar pelo teste |

### Semana 3: fechamento e review

| ID | Título | História | Frente sugerida | Pontos | Dependência | Critério de aceite |
| --- | --- | --- | --- | ---: | --- | --- |
| S2-08 | Avaliar calibração e política de limiar | US09, US11 | IA/PO | 8 | S2-01, S2-07 | Períodos de calibração/limiar separados; Brier, curva de calibração e impacto na quantidade de alertas documentados; sem promessa de melhoria |
| S2-09 | Validar back-end e preparar entrega da Sprint 2 | US07–US09, US11 | Qualidade/Equipe | 5 | S2-05, S2-06, S2-08 | Testes de permissões, persistência e integração aprovados; contrato e resultados atualizados; demonstração reproduzível |

**Entrega da review 2:** registrar um pedido com acesso autorizado, gerar e persistir uma previsão e recuperar seu histórico. Apresentar o estudo da IA, com decisão justificada de manter ou substituir o modelo inicial. Não é obrigatório trocar o modelo se os candidatos não melhorarem os critérios acordados.

O executor de experimentos, a calibração, a autenticação e a persistência acima são trabalho futuro; não fazem parte do código entregue na Sprint 1.

## Sprint 3 — Flutter, visualização e validação integrada

### Semana 1: fluxo principal

| ID | Título | História | Frente sugerida | Pontos | Dependência | Critério de aceite |
| --- | --- | --- | --- | ---: | --- | --- |
| S3-01 | Estruturar Flutter Web/Mobile e acesso autenticado | US07, US10 | Interface | 5 | S2-04, S2-05 | Projeto executável no navegador e ambiente móvel escolhido; acesso integrado à API |
| S3-02 | Implementar formulário e resultado da previsão | US03, US10 | Interface/Back-end | 8 | S3-01, S2-09 | Usuário envia pedido e vê classificação, score, versão e avisos; carregamento e erros tratados |
| S3-03 | Implementar consulta ao histórico do usuário | US08, US10 | Interface | 5 | S2-06, S3-01 | Listagem e detalhe respeitam autorização e exibem a versão do modelo usada |

### Semana 2: visualização e integração

| ID | Título | História | Frente sugerida | Pontos | Dependência | Critério de aceite |
| --- | --- | --- | --- | ---: | --- | --- |
| S3-04 | Implementar mapa e indicadores históricos por UF | US06, US10 | Interface/Dados | 8 | S3-01, endpoint histórico | Mapa exibe taxa e volume de pedidos, período e fonte; não apresenta dados históricos como previsões atuais |
| S3-05 | Verificar experiência Web/Mobile e acessibilidade | US10 | Interface/Qualidade | 5 | S3-02–S3-04 | Fluxos utilizáveis nos dois alvos, com rótulos, contraste, feedback e estados de erro revisados |
| S3-06 | Executar testes completos e preparar ambiente de demonstração | US03, US07, US08, US10 | Qualidade/Back-end | 5 | S2-09, S3-02–S3-04 | Fluxo interface → API → persistência → IA testado; configuração e recuperação de versão anterior documentadas |

### Semana 3: avaliação e entrega

| ID | Título | História | Frente sugerida | Pontos | Dependência | Critério de aceite |
| --- | --- | --- | --- | ---: | --- | --- |
| S3-07 | Realizar avaliação com usuários e corrigir problemas prioritários | US10 | Qualidade/PO/Interface | 5 | S3-05, S3-06 | Tarefas de teste definidas; feedback registrado; problemas críticos corrigidos ou explicitados |
| S3-08 | Consolidar evidências, documentação e apresentação final | US01–US11 | Equipe | 3 | S3-07 | Vídeo ou demonstração, instalação reproduzível, resultados e limitações atualizados, itens de aceite revisados |

**Entrega da review 3:** usuário acessa a aplicação, consulta risco, recupera histórico e explora atrasos observados por UF. Mostrar funcionamento Web/Mobile, evidências de testes e limites do modelo. Qualquer publicação pública deve ocorrer depois da configuração e validação do ambiente.

## Como cadastrar cada cartão

Use o ID e o título acima, com estes campos adaptados ao formulário disponível no EntregaLab. Não se presume integração nem importação automática.

```text
Título: S2-07 — Comparar configurações e analisar erros
Sprint: 2
História relacionada: US11
Objetivo: comparar candidatos para tornar os alertas mais úteis.
Atividades: executar protocolo temporal, registrar parâmetros e analisar falsos positivos/negativos.
Critério de aceite: tabela de validação temporal e decisão justificada, sem escolher pelo teste externo.
Evidências: PR, configuração dos experimentos, tabela de resultados e análise de erros.
Dependência: S2-03.
Frente sugerida: IA.
Estimativa inicial: 8 pontos, a refinar pela equipe.
Responsável individual: a definir.
Início e prazo: preencher após aprovação do calendário.
Status inicial: planejado.
```

Para cartões da Sprint 1, usar "implementado, aguardando aceite" quando esse for o estado real. Se o sistema tiver apenas "a fazer/em andamento/concluído", registrar a situação de aceite na descrição e combinar o critério de conclusão com a equipe.

## Critério comum de conclusão

Um cartão deve ter critério de aceite demonstrado, revisão da equipe, testes adequados à mudança e evidências anexadas. Na IA, anexar origem dos dados, períodos, configuração e métricas, preservando a distinção entre demonstração sintética e avaliação real. Encerramento de sprint e aceite do professor não são presumidos pelo simples fato de o código existir.
