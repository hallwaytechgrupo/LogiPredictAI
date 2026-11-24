# Resultado medido — candidato de homologação

Escolha pelo desenvolvimento: **blend_cb150_aft_extreme_0.5_3_0.5**. Foram 55 configurações e 220 comparações em quatro meses, além das previsões históricas para treinar os revisores.

Avaliação final: 19,258 pedidos, 704 atrasos. Destes, 132 já tinham prazo vencido no despacho; o modelo pode antecipar os outros 572.

| Modelo / perfil | Atrasos sinalizados dos 704 | Antecipados dos 572 | Falsos alertas | Atrasos perdidos |
|---|---:|---:|---:|---:|
| Pesos atuais da main, corte original | 564 | 434 | 4364 | 140 |
| Candidato, alvo de calibração 80% | 614 | 482 | 6929 | 90 |
| Candidato, alvo de calibração 90% | 659 | 527 | 10125 | 45 |
| Candidato, alvo de calibração 95% | 684 | 552 | 12739 | 20 |

No perfil principal, o candidato sinaliza +95 atrasos e gera +5761 falsos alertas em relação ao corte original. Isso, sozinho, não demonstra que a ordenação do novo modelo seja melhor.

Para alcançar o mesmo recall de antecipação (92.1%), o modelo original precisaria de 9513 falsos alertas no diagnóstico retrospectivo. O candidato tem quantidade **maior ou igual** (10125). Esse corte equivalente foi localizado no teste e não pode ser usado como corte de produção.

Com orçamento de até 500 falsos alertas, a ordenação do candidato chega retrospectivamente a 393 atrasos sinalizados, incluindo os 132 já vencidos. Não atingimos 600 atrasos com apenas 500 alarmes falsos. Isso não prova um limite universal.

## Revisão de alertas

| Cascata / alvo | Falsos alertas removidos do detector | Atrasos reais descartados junto |
|---|---:|---:|
| cascade_cb150_lr_hard3 / 80% | 6634 | 125 |
| cascade_cb150_lr_hard3 / 90% | 2944 | 52 |
| cascade_cb150_lr_hard3 / 95% | 1327 | 17 |

O revisor não recupera casos perdidos pelo primeiro detector. Ele foi comparado pelo mesmo critério e não foi imposto como solução obrigatória.

## Integração

O serviço candidato e o código original do serviço da main carregaram o mesmo bundle e passaram nos testes. Tempo observado da primeira requisição no teste local: 45.51 ms; é uma medida local isolada, não um teste de carga.

Nenhum arquivo existente do sistema foi alterado. O modelo atual permanece em uso. O bundle exportado contém exatamente os pesos avaliados; não foi reajustado com o período final.

## Interpretação e limites

O objetivo de 90% é definido na calibração, não uma garantia sobre pedidos futuros. O melhor candidato é o que venceu o critério de desenvolvimento entre os métodos testados. Não se pode afirmar que atingimos o melhor resultado matematicamente possível.

Os dados são Olist 2016–2018, apenas pedidos posteriormente entregues e aprovados nos filtros. O período final já foi usado em pesquisas anteriores: a comparação é retrospectiva. Validação em período novo continua necessária antes de promover o candidato.

O pacote usa as 13 entradas disponíveis no serviço atual e cruzamentos calculáveis. IDs de vendedor, CEP, categorias e históricos mais ricos existem nos dados, mas sua integração exigiria ampliar o contrato e fornecer essas mesmas informações no serviço. Não usamos campos fictícios para simular essa disponibilidade.

Veja o notebook para as métricas por família, regiões, meses, calibração, censura, incerteza e testes. Veja README.md para executar e homologar.
