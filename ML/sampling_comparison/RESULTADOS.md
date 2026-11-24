# Resultado: aumento artificial e redução de dados no treino

Preservamos os modelos de 564 acertos / 4.358 falsos alertas / 140 perdidos e de 613 acertos / 6.774 falsos alertas / 91 perdidos. Seus pesos e cortes não foram alterados.

Nove estratégias foram comparadas em quatro meses e duas referências: 72 avaliações temporais. Os detectores e o histórico real permaneceram fixos; somente o conjunto de ajuste do revisor mudou. Selecionamos estratégias por validação, incluindo a melhor de cada família para a comparação final.

| Referência | Estratégia | Atrasos encontrados | Falsos alertas | Perdidos | Precisão | Recall | Acurácia |
|---|---|---:|---:|---:|---:|---:|---:|
| base_564 | Modelo preservado | 564 | 4358 | 140 | 11.46% | 80.11% | 76.64% |
| base_564 | Controle sem amostragem | 564 | 4358 | 140 | 11.46% | 80.11% | 76.64% |
| base_564 | SMOTENC de atrasos | 564 | 4364 | 140 | 11.44% | 80.11% | 76.61% |
| base_564 | Limpeza Tomek de pontuais | 563 | 4335 | 141 | 11.49% | 79.97% | 76.76% |
| base_564 | Repetir falsos alertas difíceis | 563 | 4345 | 141 | 11.47% | 79.97% | 76.71% |
| base_564 | SMOTENC + limpeza Tomek | 564 | 4361 | 140 | 11.45% | 80.11% | 76.63% |
| base_613 | Modelo preservado | 613 | 6774 | 91 | 8.30% | 87.07% | 64.35% |
| base_613 | Controle sem amostragem | 613 | 6774 | 91 | 8.30% | 87.07% | 64.35% |
| base_613 | SMOTENC de pontuais | 613 | 6733 | 91 | 8.34% | 87.07% | 64.57% |
| base_613 | Retirada aleatória de pontuais | 609 | 6646 | 95 | 8.39% | 86.51% | 65.00% |
| base_613 | Repetir falsos alertas difíceis | 611 | 6688 | 93 | 8.37% | 86.79% | 64.79% |
| base_613 | SMOTENC + limpeza Tomek | 613 | 6821 | 91 | 8.25% | 87.07% | 64.11% |

## Conclusão desta rodada

Os controles sem amostragem venceram o critério agregado de validação nas duas referências. Nenhuma estratégia nova demonstrou vantagem consistente entre os meses para substituir automaticamente os modelos preservados.

Em base_564, nenhum candidato avaliado no período final reduziu falsos alertas mantendo a quantidade de atrasos sinalizados.

Em base_613, SMOTENC de pontuais teve ganho pontual: 613 acertos e 6733 falsos alertas, redução líquida de 41 (0.61%). Perdeu 1 caso(s) antes encontrado(s) e recuperou 1 outro(s); manter o total não significa preservar todos os mesmos pedidos. O ganho precisa de confirmação independente.

## Como avaliar o ganho

Aumentar a acurácia isoladamente não resolve o objetivo. Neste teste há 18.554 pedidos pontuais e 704 atrasados; dizer sempre “não atrasa” alcança 96,34% de acurácia e encontra zero atrasos. Por isso a seleção penaliza perder atrasos e compara a quantidade de falsos alertas com o controle.

O controle sem amostragem reproduz exatamente os dois modelos preservados. Calibração e teste mantiveram a proporção real de classes; nenhum pedido do teste foi apagado. Cortes são definidos no bloco passado real, não em dados artificiais e não pelos erros finais.

## O que foi artificial

SMOTENC gera vetores de atributos próximos de exemplos de treino da mesma rota de UFs, usando categorias existentes. Padronização e imputação para vizinhança aprendem somente no treino. Recalculamos relações determinísticas disponíveis, arredondamos contagens e restringimos valores físicos. Os exemplos reais originais são preservados; os vetores novos são acrescentados somente ao ajuste.

Esses vetores não são pedidos realmente observados. Seus rótulos são hipóteses do método, e nem todas as relações operacionais podem ser garantidas. Eles não criam novas entregas reais, não alimentam o histórico de vendedor e não são importados na aplicação. Mais linhas não significa mais informação independente.

Duplicação reutiliza linhas reais. A mineração de falsos alertas usa previsões históricas fora do treino do detector. Retirada aleatória, seleção de pontuais difíceis e Tomek atuam somente no treino. As exclusões testadas preservam todos os exemplos reais de atraso dessa etapa.

## Limitações e integração

O período final de 2018 já apareceu nas pesquisas anteriores. Os resultados são exploratórios, com semente 42, e não demonstram um limite absoluto nem confirmação independente. A população avaliada contém pedidos Olist posteriormente entregues e aprovados nos filtros.

A primeira etapa limita os acertos possíveis: a referência 564 não recupera atrasos descartados pelo seu detector. Na referência 613, o detector original ainda sinaliza até 614; reajustar o revisor pode recuperar um atraso perdido pelo filtro anterior.

Os modelos novos mantêm o contrato contextual com seller_id e prefixos CEP. O serviço deste pacote informa corretamente quando SMOTENC foi usado no treino; a geração artificial não roda na inferência. Nenhum modelo foi ativado na aplicação. Consulte README.md e o notebook.
