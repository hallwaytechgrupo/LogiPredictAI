# Ciência de dados e modelo

## Pergunta e unidade de análise

No instante do despacho, este **pedido** será entregue depois da data prometida? A Olist fornece datas por pedido; não há um identificador individual de pacote nem identificação da transportadora. Portanto, a primeira versão classifica pedidos, inclusive os que contêm vários vendedores. Ela não mede desempenho de parceiros logísticos específicos.

`is_late = 1` quando a **data de calendário** da entrega efetiva é posterior à data prometida. Entregar às 23h no dia prometido conta como entrega no prazo. Cancelados, indisponíveis e pedidos sem entrega observada ficam fora desta amostra. Isso gera um viés de seleção: o modelo cobre pedidos entregues, sem estimar cancelamento ou extravio.

## Limpeza e integração

1. Exigir os seis CSVs e suas colunas, remover duplicatas exatas e rejeitar chaves primárias conflitantes ou nulas.
2. Tratar prefixos de CEP como texto para preservar zeros iniciais. A localização é aproximada pela mediana das coordenadas de cada prefixo; valores fora dos limites de latitude e longitude viram ausentes.
3. Integrar itens com produtos, vendedores e cliente com cardinalidades verificadas. Agregar itens **antes** de juntar o resultado aos pedidos.
4. Manter pedidos entregues com compra, despacho, promessa e entrega válidos e cronologia coerente. Exigir valores financeiros não negativos e UFs brasileiras válidas.
5. Peso e dimensões não positivos viram ausentes; se algum item não tem medida, o total correspondente fica ausente para evitar subestimar o pedido. Distância também fica ausente se um trajeto não puder ser calculado.
6. Preservar ausências numéricas até o treinamento. A mediana e indicadores de ausência são ajustados **somente no treino**. Campos inteiramente ausentes recebem zero pelo `keep_empty_features`; o indicador registra a ausência.
7. Registrar contagens de entrada, exclusão e ausências em `orders.quality.json`.

## Atributos

| Feature | Definição no despacho |
| --- | --- |
| `distance_km` | Maior distância Haversine entre origens dos itens e destino, em km; não representa trajeto rodoviário |
| `total_weight_g` | Soma do peso de todos os itens, em gramas |
| `total_volume_cm3` | Soma de comprimento × largura × altura dos itens, em cm³ |
| `items_count` | Quantidade de linhas de itens do pedido |
| `sellers_count` | Quantidade de vendedores distintos |
| `price` | Soma dos preços dos itens, em reais |
| `freight_value` | Soma dos fretes dos itens, em reais |
| `dispatch_lead_days` | Tempo entre compra e despacho, em dias fracionários |
| `remaining_days` | Data prometida menos data do despacho, em dias de calendário; pode ser negativa |
| `purchase_month` | Mês da compra, de 1 a 12 |
| `dispatch_weekday` | Dia da semana do despacho, de 0 (segunda) a 6 |
| `seller_state` | UF do vendedor do primeiro item, ordenado por `order_item_id` |
| `customer_state` | UF do destino |

Compra, despacho e promessa entram na API como datas locais sem fuso, seguindo os registros Olist. O sistema não converte fusos. `feature_frame` transforma essas datas da mesma forma no treinamento e na inferência.

**Informações proibidas como features:** entrega efetiva, duração final do transporte, avaliações, comentários, atraso calculado, status final e qualquer resultado conhecido após o despacho. `delivered_at` só cria o rótulo, verifica a elegibilidade e determina quando ele fica disponível.

## Escolha inicial: Random Forest

O modelo captura relações não lineares entre distância, prazo e características dos itens, exige pouco ajuste inicial e permite inspecionar importância dos atributos. Não é uma conclusão de que ele seja superior a todos os algoritmos: nesta sprint ele é comparado à referência `DummyClassifier(strategy="prior")`. Regressão logística e gradient boosting ficam como experimentos posteriores, com o mesmo protocolo.

Configuração inicial: 250 árvores, profundidade máxima 16, mínimo de 5 observações por folha, `balanced_subsample` e semente 42. UFs usam one-hot com categorias desconhecidas ignoradas. O balanceamento atua somente no treinamento, sem reamostrar o teste.

## Avaliação temporal e maturação dos rótulos

Ordenar por despacho, reservar aproximadamente 60% para treino, 20% para validação e 20% para teste. Empates de timestamp ficam no mesmo lado do corte. No treino, excluir pedidos cuja entrega ainda não era conhecida no início da validação. Na validação, excluir pedidos cuja entrega ainda não era conhecida no início do teste. Cada período deve ter ao menos 20 registros e as duas classes.

Ajustar pré-processamento e floresta somente no treino. Selecionar o limiar com maior F1 na validação, entre 0,05 e 0,95. Medir o desempenho uma única vez no teste reservado, sem ajustar o modelo pelo resultado. O artefato salvo é o modelo avaliado, sem retreinamento com o teste.

O relatório informa precisão, recall, F1, Average Precision (AP), ROC AUC, acurácia, Brier score e matriz de confusão. Com poucos atrasos, acurácia isolada pode ser enganosa. AP é reportada como Average Precision; não é a integral trapezoidal da curva PR. Brier menor indica melhor qualidade probabilística.

## Limites e próximas validações

- A base é histórica (2016–2018), sem trânsito atual, clima, feriados, modalidades de frete ou identificação de transportadora. Não promete generalização para uma operação atual.
- A avaliação usa uma base retrospectiva de entregues; pedidos sem desfecho não estão representados. A maturação nos cortes reduz vazamento temporal, mas não elimina viés de seleção nem mudança de distribuição.
- Distâncias por CEP são aproximações em linha reta. A UF principal perde informação quando há várias origens.
- A saída `delay_probability` é o score probabilístico da floresta, **sem calibração validada**. `balanced_subsample` também pode alterar a interpretação probabilística. Não apresentar um score de 0,7 como garantia de 70% de chance real.
- O limiar maximiza F1 para a entrega acadêmica. Um limiar operacional exige discutir custo de falsos positivos, atrasos não detectados e capacidade de ação da equipe logística.
- Importância por impureza é exploratória, pode favorecer variáveis contínuas e não demonstra causalidade. Importância por permutação e calibração ficam para revisão.

Referências: [dataset oficial Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), [RandomForestClassifier](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.RandomForestClassifier.html), [prevenção de vazamento de dados](https://scikit-learn.org/stable/common_pitfalls.html), [Average Precision](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.average_precision_score.html).
