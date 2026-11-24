# Treinamento candidato para LogiPredict

Abra **LogiPredict_Treinamento_Final.ipynb**. Ele contém explicações, dados, resultados executados, comparação com os pesos da main e testes. O arquivo **RESULTADOS.md** resume as contagens obtidas. O código de treino e de inferência fica em `logipredict_final/` para que o mesmo processamento seja usado na pesquisa e na API.

## O que este pacote entrega

- Comparação temporal de 55 configurações em quatro meses de desenvolvimento: classificadores, regressão de duração, sobrevivência AFT, cascatas, combinações e maturação temporal.
- Verificador de falsos alarmes treinado com previsões históricas fora do treino do detector, preservando a disponibilidade temporal dos rótulos.
- Seleção pelo critério declarado no notebook, com alvo principal de recall de 90% na calibração. Perfis adicionais de 80% e 95%.
- Bundle compatível com `pipeline.predict_proba(frame)` e `metadata.threshold` do serviço Python da main.
- Serviço opcional de homologação, JSON real para testar e testes contra o código efetivamente versionado na main.

Não alteramos os arquivos existentes, não trocamos o modelo em uso e não enviamos commits. O pacote é um candidato de pesquisa. Uma nova tecnologia não representa automaticamente uma melhoria: consulte as contagens e a comparação em recall equivalente no notebook.

**Resultado desta execução:** o candidato encontrou mais atrasos no perfil sensível, mas não reduziu os falsos alertas em recall equivalente ao modelo original. A recomendação é preservar o modelo atual. Os pesos candidatos ficam disponíveis para pesquisa e homologação, sem ativação automática.

## Executar

Na raiz do repositório, em PowerShell:

```powershell
.\.venv\Scripts\python.exe -m pip install -e "ML/final_risk_training[research]"
```

No VS Code, selecione o Python da `.venv` como kernel e execute o notebook de cima para baixo. `RETRAIN=False` reaproveita resultados somente se os hashes do código e dos seis CSVs coincidirem. `RETRAIN=True` refaz o estudo, incluindo a segunda rodada e a avaliação final.

Os dados devem estar em `back/data/raw`, em `data/raw`, ou na pasta definida por `$env:OLIST_DATASET_PATH`. Na branch machineLearning, o carregador também consegue extrair os CSVs dos objetos Git do commit `8fbdf36cc75da4befa2c81a726bbbcf646205ed0`, em diretório temporário, sem mudar o checkout. Caso não exista nenhuma dessas fontes, a alternativa pública `kagglehub` precisa ser instalada à parte. Não há credenciais no pacote.

Para executar sem interface Jupyter, na raiz:

```powershell
.\.venv\Scripts\python.exe ML/final_risk_training/run_study.py
.\.venv\Scripts\python.exe ML/final_risk_training/refine_study.py
.\.venv\Scripts\python.exe ML/final_risk_training/finish_study.py
```

## Testar a integração sem substituir o serviço atual

Na raiz, com a venv ativa:

```powershell
$env:MODEL_DIR=(Resolve-Path "ML/final_risk_training/release").Path
python -m uvicorn logipredict_final.service:app --host 127.0.0.1 --port 8001
```

Em outro PowerShell, também na raiz:

```powershell
$body=Get-Content "ML/final_risk_training/release/example_shipment.json" -Raw
Invoke-RestMethod -Uri "http://127.0.0.1:8001/predict" -Method Post -ContentType "application/json" -Body $body
```

O Node existente aceita a resposta desse serviço: `delay_probability`, `threshold`, `predicted_late`, `model_version`, `source`, `synthetic`, `warnings`. Para uma homologação completa posterior, pode-se iniciar o backend com `$env:ML_URL="http://127.0.0.1:8001"`. O fluxo de ML do simulador passa por `/api/v1/predictions`. O `/predict` demonstrativo de regras no Node é um fluxo distinto.

Também é possível manter o serviço Python original e apontar seu `MODEL_DIR` para `release`, **depois de instalar este pacote no Python desse serviço**. O teste automatizado carrega os pesos pelo código original da main, sem modificá-lo. Esse serviço original ainda acrescenta o aviso fixo “Score não calibrado”, mesmo para este candidato; por isso o serviço isolado informa os avisos correspondentes ao novo estudo.

O arquivo `release/model.joblib` contém exatamente o candidato e o corte de 90% avaliados, não um reajuste posterior no teste. `profile_80.joblib` e `profile_95.joblib` preservam alternativas completas com seus cortes. Para experimentar outro perfil, prepare outra pasta de homologação com o bundle desejado chamado `model.joblib`; não troque somente o número do corte de uma cascata, pois sua calibração também depende dos cortes.

Carregue somente Joblib de origem confiável: o formato serializa objetos Python. As versões exatas estão em `pyproject.toml` e nos metadados. O projeto usa Python 3.12. Treinar requer os seis CSVs; servir o modelo exportado não requer os CSVs.

## Limites e dados

A previsão ocorre no despacho. O modelo recebe os 13 atributos do contrato atual e cruzamentos calculáveis: regiões/UFs, relações de peso, volume, preço, frete, distância e prazo. Os IDs e históricos individuais de vendedores existem nos dados, mas não são enviados pelo serviço atual ao modelo; não são inventados na inferência. Uma versão que os use precisa ampliar o contrato e disponibilizar o histórico causal no serviço.

A pesquisa usa pedidos Olist de 2016–2018 que foram entregues e passaram nos filtros de qualidade. Não demonstra desempenho em pedidos abertos, cancelados ou na operação atual. Os 132 pedidos já vencidos no despacho são identificados separadamente por regra. Os rótulos finais deste período já foram analisados em estudos anteriores: é um benchmark retrospectivo, não uma confirmação independente.

O pacote não prova um limite absoluto de qualidade. O melhor resultado significa o menor critério de validação entre as 55 configurações testadas. É necessário validar um período novo antes de promover o candidato ao sistema final. Nenhum corte promete encontrar todos os atrasos com poucos falsos alarmes.

Os arquivos de `artifacts/`, `release/` e o ZIP são gerados e ignorados pelo Git para evitar incluir grandes caches e pesos acidentalmente. Para transportar tudo, use o ZIP entregue junto do notebook. Para versionar o código, adicione somente esta pasta; para distribuir os pesos, use um Release, Git LFS ou armazenamento de artefatos.
