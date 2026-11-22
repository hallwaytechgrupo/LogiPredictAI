# Preparação da entrega e da feira

## Situação técnica

A base de integração foi a `main`, que reúne Flutter, Node, serviço Python,
pedidos, hubs e análises. A pesquisa de ML fica na `machineLearning`.
A branch `codex/mapa-simulacoes-final` combina a aplicação com os dois notebooks
finais, seus pesos e o novo mapa usando o modelo 564 + filtro.

O sistema já demonstra o fluxo de entrada → validação → API → modelo real →
classificação → mapa → comparação de cenários. O mapa histórico anterior está
preservado. As rotas antigas continuam utilizando seu contrato e modelo original;
o novo fluxo de pesquisa usa explicitamente `modelo_564_filter`.

O produto é uma demonstração acadêmica com dados reais históricos. A quantidade
de falsos alertas, a falta de calibração e o reuso exploratório do benchmark
impedem apresentá-lo como um serviço comercial validado.

## Antes da entrega acadêmica

| Prioridade | O que falta decidir ou preparar | Motivo |
| --- | --- | --- |
| Essencial | Revisão da integração e incorporação da branch final à `main` pela equipe | Definir uma única versão de entrega para todos os integrantes |
| Essencial | Conferir o aceite com o enunciado/rubrica oficial da ABP e atualizar os cartões no kanban | A análise do código não substitui o aceite acadêmico; a rubrica completa não está no repositório |
| Essencial | Atualizar os slides/pôster para RF + filtro CatBoost e os números finais | Evitar apresentar os resultados antigos como se fossem os do mapa atual |
| Essencial | Ensaiar o roteiro no notebook e na resolução da tela que serão usados na feira | Verificar tempo, legibilidade e operação sem depender de improviso |
| Essencial | Salvar vídeo curto e capturas de uma demonstração real | Ter uma alternativa caso energia, navegador ou computador falhe |
| Recomendado | Rodar o projeto em um segundo computador com instalação limpa | Reduzir dependência do ambiente já configurado do desenvolvedor |
| Conforme rubrica | Validar também o caminho com PostgreSQL ativo, caso seja apresentado | A verificação local desta etapa utilizou fallback JSON, com banco indisponível |
| Conforme rubrica | Homologar o build Docker e Mobile se forem entregas exigidas | Testes Web/local não equivalem a testes de implantação Linux ou de aplicativo móvel |

As pesquisas antigas e o arquivo ZIP local não entram na publicação final.
Os dois modelos selecionados estão na pasta final, com os códigos necessários
para carregar os pesos. A pasta `.venv` e os dados operacionais particulares não
devem ser adicionados com `git add .`.

## Roteiro de aproximadamente cinco minutos

1. **Problema, 40 s:** uma entrega atrasada sem aviso prejudica a experiência
   do consumidor. A plataforma ajuda a priorizar acompanhamento no despacho.
2. **Dados, 40 s:** seis tabelas públicas da Olist, integração por pedido,
   histórico anterior à previsão, vendedor real, prefixos de CEP e prazos.
3. **Demonstração, 2 min:** abrir o mapa, filtrar uma região/período, selecionar
   um pedido, simular e comparar datas. Mostrar origem/destino, faixa de risco,
   histórico disponível e uma comparação que realmente altere a faixa.
4. **Resultados, 1 min:** explicar 564 encontrados, 140 perdidos e 4.358 falsos
   alertas. Diferenciar recall de precisão, e antecipações de prazos já vencidos.
5. **Limites e evolução, 40 s:** histórico 2016–2018, scores não calibrados e
   necessidade de teste novo. Feriado aparece como contexto, sem alegar que o
   modelo aprendeu um efeito que não foi medido.

Use os três pedidos de exemplo documentados em [Mapa e demonstração](mapa-e-demonstracao.md).
São exemplos escolhidos para explicar o fluxo; não são uma amostra para medir
desempenho. As métricas apresentadas vêm dos 19.258 pedidos completos.

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

Não é necessário prometer esses itens como concluídos na feira, a menos que
façam parte do enunciado: autenticação/autorização, configurações seguras de
banco e credenciais fora do código, persistência e backup homologados, testes
de carga, observabilidade e monitoramento de mudança da distribuição dos dados.

Para ML, é preciso testar em novos pedidos/períodos que não participaram das
escolhas, calibrar o score em dados separados, definir o custo/capacidade de
tratamento dos alertas e alimentar um histórico recente e completo. Feriados
locais, transportadoras, rastreamento e eventos de entrega só devem entrar
quando existirem fontes reais disponíveis no instante da previsão.
