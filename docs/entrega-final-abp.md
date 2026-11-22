# Preparação da entrega e da feira

## Situação técnica

A versão de apresentação está na `main`, com Flutter, Node.js, serviço Python,
pedidos, hubs, análises e os dois notebooks finais com seus pesos treinados.
O mapa utiliza o modelo 564 + filtro contextual. A pesquisa e os experimentos
de ML ficam na `machineLearning`.

O sistema já demonstra o fluxo de entrada → validação → API → modelo real →
classificação → mapa → comparação de cenários. Os mapas Web usam Leaflet, com
formulário lateral para compras futuras e histórico regional em uma vista separada.
As rotas antigas mantêm seu contrato/modelo; a simulação nova usa `modelo_564_filter`.

O produto é uma demonstração acadêmica com dados reais históricos. A quantidade
de falsos alertas, a falta de calibração e o reuso exploratório do benchmark
impedem apresentá-lo como um serviço comercial validado.

## Antes da entrega acadêmica

| Prioridade | O que falta decidir ou preparar | Motivo |
| --- | --- | --- |
| Essencial | Revisar a versão integrada na `main` e definir o commit da apresentação | Todos os integrantes demonstram a mesma versão |
| Essencial | Conferir os critérios da ABP e atualizar os cartões no kanban | Relacionar funcionalidades e evidências aos critérios de avaliação |
| Essencial | Atualizar os slides/pôster para RF + filtro CatBoost e os números finais | Evitar apresentar os resultados antigos como se fossem os do mapa atual |
| Essencial | Ensaiar o roteiro no notebook e na resolução da tela que serão usados na feira | Verificar tempo, legibilidade e operação sem depender de improviso |
| Essencial | Salvar vídeo curto e capturas de uma demonstração real | Ter uma alternativa caso energia, navegador ou computador falhe |
| Recomendado | Rodar o projeto em um segundo computador com instalação limpa | Reduzir dependência do ambiente já configurado do desenvolvedor |
| Conforme rubrica | Validar também o caminho com PostgreSQL ativo, caso seja apresentado | A verificação local desta etapa utilizou fallback JSON, com banco indisponível |
| Conforme rubrica | Homologar o build Docker e Mobile se forem entregas exigidas | Testes Web/local não equivalem a testes de implantação Linux ou de aplicativo móvel |

Os notebooks, pesos, dados de avaliação e módulos de inferência estão em
`ML/modelos_finais`. Essa pasta contém os arquivos necessários à execução dos
dois classificadores. Dependências e configuração do ambiente estão descritas
no [README](../README.md).

## Roteiro de aproximadamente cinco minutos

1. **Problema, 40 s:** uma entrega atrasada sem aviso prejudica a experiência
   do consumidor. A plataforma ajuda a priorizar acompanhamento no despacho.
2. **Dados, 40 s:** seis tabelas públicas da Olist, integração por pedido,
   histórico anterior à previsão, vendedor real, prefixos de CEP e prazos.
3. **Demonstração, 2 min:** abrir **Simular nova entrega**, preencher o exemplo
   de compra em 23/12 e ajustar os campos. Mostrar origem/destino, faixa de risco,
   calendário e alternativas. Depois consultar o histórico por região.
4. **Resultados, 1 min:** explicar 564 encontrados, 140 perdidos e 4.358 falsos
   alertas. Diferenciar recall de precisão, e antecipações de prazos já vencidos.
5. **Limites e evolução, 40 s:** histórico 2016–2018, scores não calibrados e
   necessidade de teste novo. Feriado aparece como contexto, sem alegar que o
   modelo aprendeu um efeito que não foi medido.

Use **Exemplo: compra em 23/12**, documentado em [Mapa e demonstração](mapa-e-demonstracao.md).
É um cenário hipotético para explicar o fluxo, sem resultado real de entrega.
As métricas do treinamento vêm dos 19.258 pedidos históricos da avaliação.

## Respostas simples para o público

- **Ele acerta 80% de tudo?** Não. Encontrou aproximadamente 80% dos pedidos
  que realmente atrasaram, mas muitos alertas não se confirmaram.
- **Quantos alertas estavam certos?** Dos 4.922 alertas, 564 eram atrasos:
  aproximadamente 11,5 em cada 100 alertas. O uso deve considerar o custo de
  acompanhar um pedido, e não disparar promessas ou indenizações automaticamente.
- **Todos os 564 foram previstos antes do prazo vencer?** Não. Foram 434
  antecipações e 130 casos já vencidos no momento do despacho.
- **O sistema garante que trocar a data resolve?** Não. Ele compara como o
  modelo classifica as novas entradas, sem provar causa e efeito.
- **O feriado aumentou o risco?** O calendário identifica a data, mas este
  modelo não usa feriado explicitamente. Não se pode atribuir uma causa.
- **A interface treina a cada clique?** Não. Ela consulta pesos já treinados.
- **Por que não tentar mais modelos agora?** Novas buscas no mesmo teste
  podem selecionar um resultado que parece melhor por acaso. A prioridade
  passa a ser um novo período independente e dados operacionais recentes.

## Organização da feira

Instale dependências e carregue o projeto antes de chegar. Leve fonte,
extensão de energia, mouse e cópia local do repositório completo. Abra os três
serviços e confirme a pesquisa antes da apresentação. Use o mapa sem ruas se
a internet não estiver disponível. A vista histórica e serviços externos podem
ter dependência de rede; não os escolha como único caminho da demonstração.

Dividam os papéis: uma pessoa explica o problema, outra opera, outra apresenta
os dados/resultados e outra responde perguntas. Incluam no pôster um diagrama
simples Flutter → Node → Python → RF + CatBoost, um exemplo visual e a matriz
de confusão. Um QR code pode apontar para o repositório/documentação já publicada,
sem exigir a abertura de um endereço localhost no celular dos visitantes.

## Para uma operação comercial posterior

A evolução para uso comercial envolve autenticação/autorização, configuração
segura de banco e credenciais, persistência e backup homologados, testes de
carga, observabilidade e monitoramento de mudança da distribuição dos dados.

Para ML, é preciso testar em novos pedidos/períodos que não participaram das
escolhas, calibrar o score em dados separados, definir o custo/capacidade de
tratamento dos alertas e alimentar um histórico recente e completo. Feriados
locais, transportadoras, rastreamento e eventos de entrega só devem entrar
quando existirem fontes reais disponíveis no instante da previsão.
