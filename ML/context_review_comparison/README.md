# Três referências preservadas e revisão com contexto

Abra `Comparacao_Contexto_Tres_Modelos.ipynb`. `RESULTADOS.md` resume as contagens. As escolhas são feitas na validação temporal antes da nova comparação final; o período final já foi utilizado em pesquisas anteriores, portanto a comparação permanece exploratória.

## Referências separadas

- `referencias/modelo_631/`: cascata original, 631 sinalizados, 9.728 falsos alertas, 73 perdidos.
- `referencias/modelo_564/`: Random Forest da main com seu corte original, 564 sinalizados, 4.364 falsos alertas, 140 perdidos.
- `referencias/modelo_614/`: combinação CatBoost/AFT com alvo de 80%, 614 sinalizados, 6.929 falsos alertas, 90 perdidos.

Cada pasta contém `model.joblib`, `metadata.json` e `previsoes.csv`. O manifesto SHA-256 protege essas referências. Os arquivos originais de `ML/final_risk_training` continuam preservados.

## Novos testes

Para cada referência treinamos uma reavaliação com contexto (pode recuperar e descartar alertas) e um filtro com contexto (somente retira alertas). Para 614 treinamos também uma revisão adicional sobre a sua versão já enriquecida. Essa terceira etapa usa previsões históricas fora do ajuste da etapa anterior.

O contexto usa cinco grupos: global, vendedor principal, par de UFs, rota por prefixos de CEP e prefixo de destino. Entregas só entram no histórico após ocorrerem. Os 90 atributos representam contagens, frequências, durações, P50/P90 e folgas. Nenhum pedido ou desfecho foi inventado. Testamos CatBoost com categorias nativas, LightGBM e regressão logística; os modelos anteriores permanecem congelados na avaliação final.

Na comparação principal, o histórico recebe eventos já observados durante o teste, sem atualizar pesos ou cortes. O controle com histórico congelado permite medir a dependência dessa atualização. O controle sem histórico usa o mesmo revisor escolhido, para distinguir efeito de contexto de efeito de algoritmo.

Os perfis `novos_modelos/modelo_614_filter_retain975` e `modelo_614_filter_retain95` preservam os cortes predefinidos de retenção de 97,5% e 95% na calibração. Obtiveram, respectivamente, 614 acertos / 6.909 falsos alertas / 90 perdidos e 613 acertos / 6.774 falsos alertas / 91 perdidos. Esses números são do teste retrospectivo; a retenção nominal não é garantia futura. Os pesos são os mesmos do filtro de contexto, com cortes diferentes, sem reajuste usando os erros finais.

## Executar na raiz do repositório

```powershell
.\.venv\Scripts\python.exe -m pip install -e "ML/final_risk_training[research]"
.\.venv\Scripts\python.exe -m pip install -e "ML/context_review_comparison[research]"
.\.venv\Scripts\python.exe ML/context_review_comparison/prepare_data.py
.\.venv\Scripts\python.exe ML/context_review_comparison/run_study.py
.\.venv\Scripts\python.exe ML/context_review_comparison/finish_study.py
```

O estudo depende do pacote do treinamento anterior e dos objetos de referência já congelados. Não altere esse pacote enquanto compara os resultados. No ZIP completo ele acompanha as fontes em `runtime_referencias/`; instale esse diretório primeiro se estiver fora do repositório.

Selecione o Python da `.venv` como kernel do notebook. A primeira execução completa pode levar vários minutos. As células reaproveitam resultados calculados com as mesmas fontes e os mesmos dados; a opção de refazer treinos é explícita no notebook.

## Homologação isolada

Com a venv ativa e na raiz do repositório:

```powershell
$env:MODEL_DIR=(Resolve-Path "ML/context_review_comparison/novos_modelos/modelo_614_rescore").Path
python -m uvicorn context_risk.service:app --host 127.0.0.1 --port 8002
```

O JSON recebe os campos do Shipment atual e três campos adicionais opcionais:

```json
{"seller_id":"identificador_real_do_vendedor", "origin_prefix5":"01001", "destination_prefix5":"20040"}
```

São prefixos de **cinco dígitos**, preservando zeros à esquerda. O identificador precisa ser real e consistente com o histórico. O arquivo `exemplo_enriquecido.json` contém um pedido real completo para teste. Não substitua IDs ausentes por IDs inventados.

Se algum desses campos estiver ausente, o serviço devolve a previsão da referência preservada, usando seu corte original. O retorno informa `decision_source=reference_missing_context`. Isso permite homologar o contrato atual sem atribuir a ele o desempenho da versão enriquecida. Para receber o ganho contextual na aplicação final, será necessário encaminhar as identidades reais e manter o histórico de entregas atualizado; essa alteração no Node/Flutter ainda não foi ativada.

Os bundles novos recebem o pedido original completo; o `feature_frame` de apenas 13 atributos do serviço Python antigo não é suficiente. Não aponte o serviço antigo diretamente para esses bundles. Use o serviço de homologação deste pacote.

Os scores de filtros são condicionais aos alertas anteriores e não são probabilidades populacionais calibradas. Os dados Olist são de 2016–2018; precisam ser substituídos por um histórico operacional recente antes de uso real.

`artifacts/`, `referencias/`, `novos_modelos/` e ZIP são ignorados pelo Git por conter pesos/caches. O ZIP inclui os pesos para preservar e transportar os resultados; nenhum CSV bruto completo é distribuído no pacote.
