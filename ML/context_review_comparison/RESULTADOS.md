# Comparação final: contexto e revisão de alertas

As três referências foram preservadas com pesos, cortes, metadados e previsões em arquivos separados. O conjunto final contém 19.258 pedidos, 704 atrasos, dos quais 132 já estavam vencidos no despacho.

| Referência | Variante | Atrasos sinalizados | Falsos alertas | Atrasos perdidos | Antecipados |
|---|---|---:|---:|---:|---:|
| modelo_631 | Referência preservada | 631 | 9728 | 73 | 499 |
| modelo_631 | Reavaliação com contexto | 700 | 15564 | 4 | 568 |
| modelo_631 | Filtro com contexto | 631 | 9723 | 73 | 499 |
| modelo_564 | Referência preservada | 564 | 4364 | 140 | 434 |
| modelo_564 | Reavaliação com contexto | 674 | 12484 | 30 | 542 |
| modelo_564 | Filtro com contexto | 564 | 4358 | 140 | 434 |
| modelo_614 | Referência preservada | 614 | 6929 | 90 | 482 |
| modelo_614 | Reavaliação com contexto | 655 | 10390 | 49 | 523 |
| modelo_614 | Filtro com contexto | 614 | 6929 | 90 | 482 |
| modelo_614 | Contexto + revisão adicional | 655 | 10382 | 49 | 523 |

## O que os filtros retiraram

| Modelo | Falsos alertas removidos | Atrasos reais descartados |
|---|---:|---:|
| modelo_631_filter | 5 | 0 |
| modelo_564_filter | 6 | 0 |
| modelo_614_filter | 0 | 0 |
| modelo_614_contexto_mais_revisao_adicional | 8 | 0 |

## Perfis adicionais do filtro 614

| Retenção alvo na calibração | Atrasos sinalizados | Falsos alertas | Perdidos |
|---|---:|---:|---:|
| 97.5% | 614 | 6909 | 90 |
| 95.0% | 613 | 6774 | 91 |

A revisão adicional do modelo 614 é comparada à sua versão já enriquecida, não diretamente à referência original. O filtro simples de 614 é comparado à referência original. Filtros não podem recuperar pedidos que sua etapa anterior descartou.

## Critério e dados

As quatro configurações de revisor são comparadas em dezembro/2017 e fevereiro, março e abril/2018. A reavaliação procura reduzir FPR penalizando perda de recall em relação à referência. O filtro procura reduzir a proporção de falsos alertas e penaliza retenção abaixo de 98% dos atrasos da referência. O perfil principal procura preservar 99% dos acertos no bloco de calibração passado; isso não garante retenção igual no teste.

Os revisores aprendem com previsões de réplicas históricas feitas antes do período previsto, excluindo o bloco de calibração e rótulos ainda desconhecidos. A terceira etapa recebe previsões temporais do próprio modelo enriquecido, sem treinar sobre seus acertos no próprio ajuste.

O contexto usa somente entregas concluídas antes do despacho: histórico global, vendedor principal, par de UFs, rota por prefixos de CEP de três dígitos e destino. Calculamos contagens, taxas de atraso suavizadas, duração média, P50/P90 e folga do prazo, em janelas de 30/90 dias e histórico acumulado. A suavização usa a taxa global anterior ao pedido, com força fixa 20; não cria pedidos ou desfechos.

## Como interpretar a atualização do histórico

A comparação principal simula o histórico sendo atualizado conforme entregas anteriores ocorrem durante o teste. Nenhum evento na hora da previsão ou depois dela pode ser usado. Pesos e cortes permanecem fixos. O relatório controls.csv também mostra o resultado com histórico congelado no início do teste e o controle sem atributos históricos.

É uma comparação retrospectiva com Olist 2016–2018; o mesmo período final já foi examinado antes. Não é uma confirmação independente nem prova de qualidade máxima. A população contém apenas pedidos posteriormente entregues e aprovados nos filtros. O histórico do vendedor é do vendedor principal; pedidos com vários vendedores não têm seus pacotes individualizados.

## Integração

Os novos modelos exigem serviço que receba datas originais e seller_id, origin_prefix5 e destination_prefix5. A aplicação atual não fornece todos esses campos ao modelo. O serviço de homologação oferecido preserva a previsão da referência quando faltam essas identidades, com aviso explícito. Os resultados enriquecidos não devem ser prometidos para entradas sem esses campos.

Nenhuma versão foi ativada na aplicação e nenhum arquivo anterior foi substituído. README.md explica execução e homologação. O notebook contém os resultados, os controles e os testes.
