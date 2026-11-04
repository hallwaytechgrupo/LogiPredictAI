# Relatório de treinamento

Fonte: **olist**. Modelo: `rf-olist-b96c2d0272d8`. Hash SHA-256: `b96c2d0272d83a6440950c73604dab2748dd4328cb0aaf862875c69469853782`.
Base histórica Olist; resultados não garantem desempenho em operações atuais.

Divisão por despacho: 60% / 20% / 20%, com remoção de rótulos ainda indisponíveis nos cortes.
Treino: 54761; validação: 17445; teste: 19258; removidos nos cortes: 4817.
Limiar selecionado somente na validação: 0.37. O artefato mantém o modelo avaliado, sem retreino no teste.

| Métrica de teste | Random Forest | Baseline majoritária |
| --- | ---: | ---: |
| accuracy | 0.7661 | 0.9634 |
| precision | 0.1144 | 0.0000 |
| recall | 0.8011 | 0.0000 |
| f1 | 0.2003 | 0.0000 |
| average_precision | 0.3708 | 0.0366 |
| roc_auc | 0.8677 | 0.5000 |
| brier_score | 0.1008 | 0.0354 |

Probabilidade não calibrada; limiar acadêmico por F1 ainda requer validação do custo dos erros.
AP significa Average Precision, não a integral trapezoidal da curva PR.
Matriz: linhas = classes reais; colunas = previstas; ordem = [no prazo, atraso].

![Matriz de confusão](confusion_matrix.png)
![Curva de precisão e recall](precision_recall.png)
![Importância dos atributos](feature_importance.png)
