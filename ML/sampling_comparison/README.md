# Amostragem artificial e limpeza do treino

Preservamos duas referências em `preservados`: **564 + filtro** (564 acertos, 4.358 falsos alertas, 140 perdidos) e **614 + filtro mais restritivo** (613 acertos, 6.774 falsos alertas, 91 perdidos). Seus pesos e cortes originais não são modificados.

Abra `Teste_Amostragem_Artificial_e_Limpeza.ipynb`. `RESULTADOS.md` mostra as contagens finais, e `modelos_novos/` guarda as versões avaliadas separadamente. O estudo é exploratório: o período final de 2018 já apareceu em pesquisas anteriores.

## O que foi testado

Mudamos somente os exemplos usados para ajustar o revisor contextual CatBoost, mantendo sua arquitetura de 350 árvores e profundidade 6. Os detectores anteriores e o histórico de entregas reais permanecem fixos. Isso isola o efeito da amostragem e preserva o fluxo de inferência.

As nove estratégias são: controle sem alteração, duplicação de atrasos, SMOTENC de atrasos, SMOTENC de pontuais, retirada aleatória de metade dos pontuais, manutenção da metade mais difícil dos pontuais, limpeza Tomek de pontuais, repetição de falsos alertas difíceis e SMOTENC combinado com Tomek.

SMOTENC interpola atributos numéricos entre vizinhos do treino e escolhe categorias existentes. Restringimos a geração ao mesmo par de UFs, padronizamos números somente para calcular vizinhança e reparamos relações determinísticas disponíveis. Rotas com poucos vizinhos são ignoradas. As novas linhas são vetores hipotéticos, não entregas verdadeiras; seu rótulo é uma suposição do método.

Os vetores artificiais nunca entram no histórico de vendedor nem são importados no sistema. Os exemplos reais originais mantêm seus valores. A limpeza remove somente pontuais do treino; nenhum atraso real é excluído nessa etapa. Dados de calibração e teste permanecem reais e completos.

## Avaliação

São quatro meses de validação temporal em cada referência, totalizando 72 avaliações. O revisor aprende com previsões históricas feitas fora do treino do detector, com rótulos já disponíveis e bloco de calibração separado.

O corte é definido no bloco real passado: retenção de 99% para a referência 564 e de 95% para a referência 613, como nas versões preservadas. A seleção compara falsos alertas com o controle e penaliza perda de atrasos. Exportamos o controle e as estratégias escolhidas por família, sem escolher o corte pelos erros finais.

O teste final tem os mesmos 19.258 pedidos reais e 704 atrasos. Não apagamos pedidos difíceis, falsos alertas ou erros desse teste. As contagens separam antecipações de prazos já vencidos. A acurácia é mostrada, mas não é o objetivo isolado: prever sempre “pontual” já alcançaria 96,34% de acurácia e encontraria zero atrasos.

## Executar na raiz do repositório

```powershell
.\.venv\Scripts\python.exe -m pip install -e "ML/final_risk_training[research]"
.\.venv\Scripts\python.exe -m pip install -e "ML/context_review_comparison[research]"
.\.venv\Scripts\python.exe -m pip install -e "ML/sampling_comparison[research]"
.\.venv\Scripts\python.exe ML/sampling_comparison/run_study.py
.\.venv\Scripts\python.exe ML/sampling_comparison/finish_study.py
```

Selecione o Python da `.venv` no notebook. `RETRAIN=True` refaz os ajustes. O cache só pode ser reaproveitado com as mesmas fontes e o mesmo manifesto de dados. Os seis CSVs Olist devem estar no projeto, nos objetos Git do commit registrado ou em `OLIST_DATASET_PATH`.

O estudo pode ser executado por referência com `run_base.py base_564` e `run_base.py base_613`. Cada processo usa quatro threads. A execução entregue reuniu referências independentes em paralelo; isso não modifica amostras, sementes ou critérios.

No ZIP completo, as fontes dos pacotes anteriores acompanham os pesos em `runtime_final/` e `runtime_context/`. Instale primeiro esses diretórios se estiver fora do repositório. `training_inputs` contém os scores históricos congelados necessários para reproduzir o treino dos revisores; não contém os seis CSVs brutos.

## Homologação

Depois de escolher uma pasta de `modelos_novos`, com a venv ativa:

```powershell
$env:MODEL_DIR=(Resolve-Path "ML/sampling_comparison/modelos_novos/NOME_DO_MODELO").Path
python -m uvicorn sampling_risk.service:app --host 127.0.0.1 --port 8003
```

Em outro terminal:

```powershell
$body=Get-Content "ML/sampling_comparison/exemplo_real.json" -Raw
Invoke-RestMethod -Uri "http://127.0.0.1:8003/predict" -Method Post -ContentType "application/json" -Body $body
```

O contrato contextual precisa de `seller_id`, `origin_prefix5` e `destination_prefix5`, além do Shipment original. Sem essas identidades, o serviço retorna a etapa original de referência e avisa que o revisor não foi usado. O retorno informa quando o revisor utilizou vetores sintéticos no treino; não executa SMOTENC durante a previsão.

São scores condicionais aos alertas anteriores e não probabilidades populacionais calibradas. Aumentar, duplicar ou retirar exemplos muda a distribuição de treinamento, o que reforça a necessidade de definir o corte usando dados reais. Nenhuma versão foi ativada na aplicação.

Os pesos, cópias preservadas e caches são ignorados pelo Git; o ZIP completo transporta os resultados. Carregue apenas Joblib de origem confiável. Consulte as limitações, as auditorias e as verificações no notebook antes de decidir pelo modelo final.
