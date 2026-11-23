# Roteiro de validação manual — Simulador de Previsão de Atrasos

Este roteiro prepara a validação funcional com os serviços reais. Ele não foi
executado automaticamente nesta etapa.

## Pré-condições

- Flutter Web disponível.
- API Node.js em `127.0.0.1:3001`.
- Serviço Python/FastAPI em `127.0.0.1:8000`.
- Modelo Olist carregado.
- Hubs e base geográfica disponíveis.

## Fluxo principal

1. Abrir a aba **Simulador Logístico**.
2. Preencher manualmente origem, destino, datas, peso, itens, valor e frete.
3. Executar **Simular operação logística**.
4. Confirmar que o score aparece como **Score previsto de atraso**.
5. Conferir classificação, threshold, versão do modelo e warnings.
6. Conferir que o painel de despacho, hubs, distâncias e mapa continuam visíveis.
7. Selecionar **Criar cenário alternativo**.
8. Confirmar que os valores alternativos começam iguais aos originais.
9. Alterar uma variável, por exemplo, o peso ou a data prometida.
10. Confirmar que o formulário original não foi alterado.
11. Executar **Prever atraso neste cenário**.
12. Conferir os dois scores reais, classificações, thresholds, versões e warnings.
13. Conferir a diferença em pontos percentuais.
14. Conferir a tabela de campos alterados, com valores original e alternativo.
15. Confirmar a observação de que a comparação não comprova causalidade.
16. Selecionar **Restaurar valores originais**.
17. Confirmar que os campos alternativos retornaram aos valores base.
18. Confirmar que a previsão alternativa e a comparação foram removidas.
19. Confirmar que o resultado original permaneceu disponível.

## Cenários de erro e concorrência

1. Iniciar uma previsão e alterar os campos enquanto ela está carregando.
2. Confirmar que a resposta antiga não reaparece depois da alteração.
3. Interromper ou tornar indisponível a geolocalização e confirmar uma mensagem específica.
4. Tornar o serviço Random Forest indisponível e confirmar erro de previsão sem apagar o despacho.
5. Executar uma previsão alternativa inválida e confirmar que o resultado original permanece.
6. Restaurar durante o carregamento alternativo e confirmar que a resposta pendente é descartada.

## Pedido importado e persistência

1. Ativar **Utilizar pedido importado**.
2. Pesquisar e selecionar um pedido.
3. Confirmar o preenchimento do formulário original.
4. Executar a previsão base.
5. Criar e executar um cenário alternativo.
6. Confirmar que a previsão hipotética não envia `order_id` e não cria histórico persistido.

## Navegação e despacho

1. Navegar para Mapa, Pedidos, Analytics e Gestão de Hubs.
2. Retornar ao Simulador Logístico.
3. Confirmar que o formulário, resultados e estado visual permanecem coerentes.
4. Confirmar que o despacho original continua exibindo hubs, distâncias, duração,
   rota e avisos quando disponíveis.

## Resultados esperados

- Os scores são retornados pelo modelo, sem cálculo local de probabilidade.
- O threshold e a versão vêm da resposta da API.
- Warnings do serviço ML permanecem visíveis.
- A diferença é apresentada em pontos percentuais.
- Nenhuma alteração é descrita como garantia de entrega ou redução causal de atraso.
- Falhas alternativas não removem resultados base válidos.
