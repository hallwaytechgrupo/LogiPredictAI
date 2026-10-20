# Explicação do projeto, testes e evolução do modelo

## Explicação curta para a apresentação

O LogiPredict AI é uma plataforma em desenvolvimento para apoiar o acompanhamento de entregas no e-commerce. A primeira versão usa dados históricos da Olist para aprender relações entre distância, características dos produtos, origem, destino e prazo prometido. No momento do despacho, o sistema estima um score de risco de atraso por pedido.

Na Sprint 1, implementamos a preparação dos dados, o treinamento Random Forest e uma API Node.js conectada ao serviço Python. Já conseguimos enviar um pedido por HTTP e receber uma classificação, além de consultar indicadores históricos por UF. A interface Flutter, os usuários e o armazenamento dos pedidos serão desenvolvidos nas próximas etapas.

O primeiro modelo encontrou 534 dos 704 atrasos do teste, mas também produziu 3.625 falsos alertas. A próxima etapa da IA é estudar esses erros e melhorar a utilidade dos alertas, sem escolher configurações pelo resultado do teste reservado.

## O caminho dos dados

1. **Obtenção:** baixar seis CSVs oficiais Olist: pedidos, itens, produtos, clientes, vendedores e geolocalização.
2. **Preparação:** verificar duplicatas, chaves, datas, UFs e valores; integrar as tabelas e preservar uma linha por pedido.
3. **Features:** calcular distância aproximada, peso e volume totais, quantidades, preços, frete, tempo até o despacho e prazo restante.
4. **Rótulo:** marcar atraso quando a entrega acontece em data de calendário posterior à promessa. A entrega real só serve para saber a resposta histórica e a disponibilidade desse resultado; não é uma entrada do modelo.
5. **Treinamento:** a Random Forest aprende padrões a partir do período de treino. Validação define o limiar; teste mede o resultado da configuração congelada.
6. **Inferência:** o serviço Python aplica as mesmas transformações a um pedido novo e retorna seu score. A API Node.js oferece esse resultado ao cliente HTTP e, futuramente, ao Flutter.

O sistema prevê **risco**, sem calcular uma data alternativa de entrega. Agregados históricos por UF descrevem entregas observadas; não representam risco previsto em tempo real. A Olist não informa a transportadora nem um registro individual por pacote.

## O que significam os números atuais

| Medida | Resultado | Como explicar |
| --- | ---: | --- |
| Recall | 75,85% | Entre os pedidos que atrasaram, o modelo sinalizou aproximadamente 76 em cada 100 |
| Precisão | 12,84% | Entre os pedidos sinalizados, aproximadamente 13 em cada 100 realmente atrasaram |
| F1 | 0,2196 | Resumo do equilíbrio entre precisão e recall no limiar usado |
| Average Precision | 0,3692 | Avalia a ordenação dos pedidos por risco; baseline = 0,0366 |
| ROC AUC | 0,8667 | Avalia a separação das classes ao variar o limiar; não é percentual de acertos |
| Acurácia | 80,29% | Percentual total de classificações corretas; isoladamente é pouco informativo com poucos atrasos |
| Brier score | 0,1018 | Avalia o erro probabilístico; nesta base a baseline foi melhor, com 0,0354 |

Não apresentar "75,85% de acerto": esse número é recall. O limiar atual é 0,39. O score não calibrado não permite afirmar que um pedido com saída 0,70 tenha comprovadamente 70% de chance real de atrasar.

## Testar a aplicação nesta máquina

No PowerShell:

```powershell
cd C:\Users\daffa\Desktop\ABP5dsm\LogiPredictAI
.\.venv\Scripts\python.exe scripts/run_local.py
```

Abra `http://127.0.0.1:8000/docs`. Esse Swagger chama diretamente o serviço Python. Para demonstrar o caminho completo pela API Node.js, em **outro terminal** use os comandos abaixo:

```powershell
cd C:\Users\daffa\Desktop\ABP5dsm\LogiPredictAI
Invoke-RestMethod http://127.0.0.1:3001/ready
$pedido = Get-Content examples/prediction.json -Raw | ConvertFrom-Json
$json = $pedido | ConvertTo-Json
Invoke-RestMethod http://127.0.0.1:3001/api/v1/predictions -Method Post -ContentType 'application/json' -Body $json
Invoke-RestMethod http://127.0.0.1:3001/api/v1/analytics/states
```

### Cenários manuais

| Cenário | Como variar | Resultado esperado |
| --- | --- | --- |
| Pedido válido | Enviar o exemplo sem alterações | HTTP 200, score, classificação, limiar e versão |
| UF inválida | Definir `customer_state` como `XX` | HTTP 422 |
| Quantidade inválida | Definir `items_count` como -1 | HTTP 422 |
| Distância ausente | Definir `distance_km` como null | HTTP 200 com aviso de preenchimento por estatística de treino |
| Cronologia inválida | Definir despacho antes da compra | HTTP 422 |
| Informação futura | Adicionar campo `delivered_at` | HTTP 422 |
| Modelo ausente | Iniciar com pasta de modelo inexistente | O iniciador local informa erro e não inicia a aplicação |
| Porta ocupada | Executar o iniciador novamente nas mesmas portas | O iniciador informa o conflito |

Exemplo de erro esperado:

```powershell
$invalido = Get-Content examples/prediction.json -Raw | ConvertFrom-Json
$invalido.customer_state = 'XX'
Invoke-RestMethod http://127.0.0.1:3001/api/v1/predictions -Method Post -ContentType 'application/json' -Body ($invalido | ConvertTo-Json)
```

O PowerShell exibirá o erro HTTP 422, pois a entrada é inválida. Isso comprova a validação.

Para explorar cenários válidos, altere distância ou data prometida no objeto `$pedido` e envie novamente, mantendo coerência entre rota, datas e atributos. Não há garantia de que mudar isoladamente uma variável faça o score crescer ou diminuir: a floresta combina várias features e não impõe monotonicidade.

**Enviar cenários não treina o modelo.** A API atual também não armazena essas consultas. Sem o resultado real posterior da entrega, elas não viram exemplos rotulados para aprendizado.

## Rodar os testes automatizados

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check ml scripts
npm.cmd test --prefix api
npm.cmd run check --prefix api
```

Com os serviços já iniciados, executar:

```powershell
.\.venv\Scripts\python.exe scripts/smoke_test.py
```

Ou encerrar os serviços com Ctrl+C e executar `python scripts/run_local.py --smoke` com o Python do ambiente virtual. Esse modo inicia os serviços, testa a integração e os encerra.

## Reproduzir o treinamento existente

O ambiente e o CSV processado já existem nesta máquina. Para repetir a configuração de 250 árvores em outra pasta, sem substituir o modelo atual:

```powershell
.\.venv\Scripts\python.exe -m logipredict.train --source olist --trees 250 --model-dir models/reproducao-250 --report-dir reports/local/reproducao-250
```

O modelo é treinado do zero. Com a mesma base, parâmetros e versões, espera-se reproduzir as métricas da configuração atual. O procedimento não acumula aprendizado de uma execução para outra.

Para servir essa cópia, encerre os serviços anteriores e execute:

```powershell
.\.venv\Scripts\python.exe scripts/run_local.py --model-dir models/reproducao-250
```

O treino usa CPU e `n_jobs=-1`, podendo utilizar todos os núcleos disponíveis. O projeto atual não usa GPU para a Random Forest. Aumentar a quantidade de árvores aumenta o trabalho computacional e não garante melhoria da previsão.

## Evoluir o modelo com um protocolo de experimentos

O comando atual é de **treinamento e avaliação completa**: ele sempre calcula métricas no teste. Não foi implementado ainda um comando dedicado à busca de configurações apenas em validação. Não usar repetidas execuções para escolher a configuração que melhor se saiu no teste histórico.

Plano para a Sprint 2:

1. Criar um executor de experimentos que mantenha o teste externo fora da seleção e compare configurações nas janelas temporais anteriores a ele.
2. Em cada janela, permitir no treinamento apenas pedidos cujo resultado já fosse conhecido no início da janela seguinte. Um corte temporal simples por número de linhas, sem essa remoção, não resolve a maturação dos rótulos.
3. Definir antes dos experimentos o custo dos falsos alertas, a capacidade de acompanhamento e a métrica prioritária. Exemplo de objetivo a negociar: elevar precisão mantendo um recall mínimo acordado. Não inventar uma meta numérica já aprovada.
4. Comparar poucas configurações justificadas: quantidade de árvores, profundidade, mínimo de exemplos por folha e balanceamento. Comparar também uma regressão logística de referência. Avaliar AP, precisão/recall e quantidade de alertas; registrar tempo de treino.
5. Separar períodos de ajuste do estimador, calibração e escolha do limiar dentro do desenvolvimento, sem sobrepor os dados usados para ensinar e medir a calibração. Preservar a cronologia e a disponibilidade dos rótulos em cada etapa.
6. Congelar features, configuração e regra de decisão; depois avaliar no teste externo e documentar o resultado, mesmo se piorar. Como o teste atual já foi observado, declarar seu uso como benchmark histórico. Se ele passar a orientar decisões, exigir um novo conjunto independente para uma alegação de desempenho final.
7. Registrar cada experimento com ID próprio, parâmetros, hash da base, versão do código, períodos e métricas. Hoje o `model_version` deriva da origem e do hash do CSV; mudar só parâmetros pode manter o mesmo identificador. Acrescentar um identificador da configuração antes de manter vários candidatos em operação.
8. Manter o modelo atual como referência até aprovar um substituto. Implantar um modelo novo apenas após revisão de resultados e verificação da integração.

Não gerar dados artificiais para alegar melhoria real na logística. Dados sintéticos são úteis para testar o funcionamento do software. Para aumentar a base real, é necessário obter novos pedidos e seus desfechos legítimos; a Olist histórica é finita.

Referências técnicas: [separação temporal e validação](https://scikit-learn.org/stable/modules/cross_validation.html), [ajuste de hiperparâmetros](https://scikit-learn.org/stable/modules/grid_search.html), [calibração de probabilidades](https://scikit-learn.org/stable/modules/calibration.html) e [métricas de avaliação](https://scikit-learn.org/stable/modules/model_evaluation.html).
