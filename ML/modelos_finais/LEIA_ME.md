# Modelos de classificação de risco

Os dois notebooks principais são:

- `Modelo_564_atrasos_4358_falsos_alertas_140_perdidos.ipynb`: Random Forest com filtro contextual; 564 atrasos sinalizados, 4.358 falsos alertas e 140 atrasos perdidos.
- `Modelo_613_atrasos_6774_falsos_alertas_91_perdidos.ipynb`: CatBoost e sobrevivência AFT com filtro contextual; 613 atrasos sinalizados, 6.774 falsos alertas e 91 atrasos perdidos.

## Abrir no VS Code

1. Abra esta pasta ou expanda `ML > modelos_finais` no explorador do projeto.
2. Abra um dos arquivos `.ipynb`.
3. Escolha o Python de `.venv\Scripts\python.exe` do projeto como kernel.
4. Use **Executar Tudo / Run All** para carregar os pesos e conferir o resultado.

A execução padrão não treina novamente e não substitui nenhum modelo. Os comentários explicam a preparação da entrada, as duas etapas de classificação, o histórico, os limites de decisão e a avaliação.

## Arquivos de apoio

Mantenha as pastas abaixo junto dos notebooks:

- `artefatos`: pesos selecionados, metadados e hashes de integridade.
- `dados`: pedidos reais da avaliação, resultados preservados e previsões temporais utilizadas no ajuste do filtro.
- `codigo`: funções de transformação, histórico, validação, inferência e reajuste opcional.

Os pesos são os mesmos dos dois modelos selecionados. Os notebooks carregam os módulos locais de `codigo`, sem depender das pastas dos testes anteriores. Os dados fornecidos bastam para executar a avaliação e o exemplo de previsão.

## Dependências

O ambiente `.venv` do projeto já contém as versões utilizadas. Para preparar outro ambiente com Python 3.12, instale `requirements.txt` no Python que será selecionado como kernel:

```powershell
python -m pip install -r requirements.txt
```

## Reajuste opcional

O bloco `REAJUSTAR_FILTRO=False` mantém os pesos selecionados. Alterar para `True` refaz somente o CatBoost revisor, usando as mesmas configurações e a primeira etapa já treinada. O arquivo de pesos original não é sobrescrito.

Esse reajuste exige os seis CSVs Olist completos. O carregador procura os arquivos no projeto, no commit registrado ou na pasta definida por `OLIST_DATASET_PATH`. Os hashes precisam corresponder à base documentada em `dados/origem.json`.

## Interpretação

A avaliação contém 19.258 pedidos e 704 atrasos. No modelo de 564, 434 casos foram antecipados e 130 já estavam com prazo vencido no despacho. No modelo de 613, 481 foram antecipados e 132 já estavam vencidos. Os notebooks mostram as duas contagens separadamente.

Os scores dos filtros não são probabilidades populacionais calibradas. O modelo contextual exige identificador real do vendedor e prefixos CEP de cinco dígitos. Para integração operacional, esses campos e os eventos reais de entrega precisam estar disponíveis e atualizados.

Os dados Olist são de 2016–2018 e os resultados são retrospectivos, referentes a pedidos posteriormente entregues que passaram nos filtros de qualidade. A aplicação não é alterada ou iniciada por estes arquivos.
