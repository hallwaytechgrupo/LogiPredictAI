"""Monta o roteiro didático. Os resultados são preenchidos executando as células."""
from pathlib import Path
import nbformat as nbf

root=Path(__file__).resolve().parent
nb=nbf.v4.new_notebook()
cells=[]
def md(text):cells.append(nbf.v4.new_markdown_cell(text.strip()))
def code(text):cells.append(nbf.v4.new_code_cell(text.strip()))

md('''# LogiPredict — treinamento temporal e revisão de alertas

**Objetivo:** antecipar o maior número de atrasos reais com o menor número de falsos alertas possível. Não há um único máximo para os dois objetivos: aumentar a sensibilidade costuma aumentar os alertas. Por isso comparamos métodos sob critérios escritos antes da avaliação final.

Este notebook executa uma pesquisa reproduzível, explica as escolhas e exporta um candidato para homologação. **Não substitui automaticamente o modelo da aplicação.** Os notebooks anteriores e os arquivos existentes do projeto permanecem preservados.

O resultado será o melhor **entre as configurações avaliadas, pelo critério declarado**, não uma prova de que nenhuma técnica futura poderia melhorar. O conjunto histórico final já apareceu nas pesquisas anteriores: esta é uma comparação retrospectiva, não uma confirmação independente.''')
md('''## 1. Ambiente e organização

Pandas e NumPy organizam os dados. Scikit-learn fornece transformações, Random Forest, regressão logística e métricas. CatBoost, LightGBM e XGBoost oferecem alternativas de árvores. XGBoost AFT estima o tempo até a entrega. Joblib salva os mesmos objetos avaliados. FastAPI e Pydantic permitem verificar o contrato do serviço final.

Instale o pacote e o ambiente de pesquisa a partir da raiz do repositório:

```powershell
.\\.venv\\Scripts\\python.exe -m pip install -e "ML/final_risk_training[research]"
```

Execute o comando na **raiz do repositório**. Selecione o Python dessa `.venv` como kernel do notebook. O diretório `logipredict_final` acompanha o notebook e contém as funções comentadas reutilizadas na API.''')
code('''# Limitamos as threads para não ocupar todo o computador durante a busca.
import os
for variable in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:
    os.environ[variable]='4'
from pathlib import Path
import json,hashlib,joblib
import numpy as np
import pandas as pd
from IPython.display import display,Markdown,Image
import logipredict_final
from logipredict_final.data import load_orders,shipment_row
from logipredict_final.features import feature_frame,enrich,FEATURES
from logipredict_final.experiment import *
from logipredict_final.evaluation import evaluate_selected,compare_shipped_model,export_selected
from logipredict_final.checks import verify
from logipredict_final.reporting import diagnostics,write_report
from logipredict_final.refinements import run_refinements,run_maturity
ROOT=Path(logipredict_final.__file__).resolve().parents[1]
WORK=ROOT/'artifacts'
WORK.mkdir(exist_ok=True)
RETRAIN=False  # True refaz a busca inteira; False reaproveita somente cache compatível.
print('Pacote:',ROOT)
print('Critério principal: alvo de recall de 90% na calibração, avaliado no mês seguinte.')''')
md('''## 2. Dados reais usados

Lemos seis tabelas Olist: **pedidos, itens, clientes, produtos, vendedores e geolocalização**. Todos os itens de um pedido entram na soma de peso, volume, preço e frete. Quando há mais de um vendedor, a distância usada é a maior distância até o cliente e a UF de origem é a do primeiro item, convenção que precisa ser mantida ao montar a entrada real.

Os CEPs de cinco dígitos localizam coordenadas medianas, após remoção de duplicatas e coordenadas fora dos limites geográficos usados para o Brasil. A distância é em linha reta: não representa uma rota rodoviária. CEP é um identificador, não uma grandeza numérica em que CEP maior signifique maior distância.

Mantemos pedidos entregues com datas consistentes. Não inventamos pedidos, desfechos, vendedores, feriados ou medidas ausentes. As ausências numéricas são preenchidas com a mediana aprendida **somente no ajuste de cada modelo**, com indicador de ausência. O manifesto registra linhas e SHA-256 de cada arquivo. Os dados podem vir de `OLIST_DATASET_PATH`, da pasta do projeto ou dos objetos Git da main no commit fixado no código, sem trocar a branch.''')
cells[-1].source+='\n\nDefinimos **atraso como classe positiva (1)**. Nesta base filtrada, os atrasos são a minoria: aproximadamente 6,8%; os pedidos pontuais representam 93,2%. Por isso acertar quase todos os pontuais, sozinho, não demonstra que estamos encontrando atrasos.'
code('''# A leitura real também valida a origem do cache; trocar o CSV exige um novo treino.
data,manifest=load_orders()
display(pd.Series(manifest['quality'],name='Quantidade'))
display(pd.DataFrame(manifest['manifest']))
TEST_START=data.dispatched_at.iloc[int(len(data)*.8)]
test=data.loc[data.dispatched_at.ge(TEST_START)]
print('Início do período final:',TEST_START)
display(pd.DataFrame({
    'Grupo':['Período final inteiro','Prazo já vencido no despacho','Ainda era possível antecipar'],
    'Pedidos':[len(test),int(test.already_overdue.sum()),int((~test.already_overdue).sum())],
    'Atrasos':[int(test.is_late.sum()),int(test.already_overdue.sum()),int(test.loc[~test.already_overdue,'is_late'].sum())]
}))''')
md('''## 3. O que o modelo pode saber

A previsão acontece **no despacho**, não na compra. O alvo é `data real da entrega > data prometida`, comparando dias de calendário. A entrega real e o status final servem para medir acertos; não entram como atributos.

O serviço Python da main transforma o JSON em 13 atributos. Preservamos esse contrato: peso, volume, distância, itens, vendedores, preço, frete, tempo entre compra e despacho, dias restantes, mês da compra, dia da semana do despacho e UFs.

A partir desses dados acrescentamos: regiões brasileiras, par de UFs, mesma UF ou interestadual, peso/preço/frete por item, densidade, frete em relação ao preço, distância em relação ao prazo, proporção do prazo consumida no despacho, logaritmos de medidas, fins de semana e meses de pico. São cálculos sobre dados existentes, não novos fatos.

**IDs de vendedores, CEPs, categoria e histórico individual existem nos CSVs, mas não chegam ao modelo no contrato atual da main.** As pesquisas anteriores exploraram parte deles. Este candidato prioriza funcionamento real no serviço existente; não promete explorar todas as entradas possíveis. Feriados específicos precisam de data completa/localidade; essas informações também são descartadas no frame atual. Usar esses atributos na próxima versão exige ampliar explicitamente o contrato e manter um histórico causal disponível na inferência. Não preenchemos identidades ou taxas históricas fictícias para esconder essa diferença.''')
code('''# A mesma função monta a entrada no treinamento e no serviço candidato.
x=feature_frame(data.iloc[:3])
display(x)
display(pd.Series(enrich(x).columns,name='Atributos após cruzamentos'))
print('Contrato original:',len(FEATURES),'atributos; após cruzamentos:',enrich(x).shape[1])''')
md('''## 4. Como evitamos aprender o futuro

Não embaralhamos pedidos entre treino e teste. Avaliamos quatro meses futuros: dezembro/2017 e fevereiro, março e abril/2018. Para cada início de mês E:

1. Somente despachos anteriores a E podem participar do treino.
2. O bloco entre E−35 e E−14 dias fica reservado para calibração e nunca entra no ajuste do detector.
3. Nos classificadores, só usamos rótulos já conhecidos em E: entrega já ocorrida, ou fim do dia prometido já ultrapassado sem entrega. Na sobrevivência, entregas ainda desconhecidas entram como observações censuradas, sem ler sua data futura.
4. A mediana e o vocabulário das categorias são aprendidos novamente em cada ajuste.
5. A decisão é avaliada nos despachos do mês seguinte. Para selecionar modelos, os desfechos desses meses precisam estar disponíveis antes do início do período final.

O detector pode usar pedidos anteriores a E que sejam mais recentes que o bloco de calibração. Portanto o bloco é uma amostra passada separada, **não** uma simulação em que todo treino é anterior à calibração. A avaliação futura começa sempre depois de ambos.

Pedidos cujo prazo já venceu no despacho são sinalizados por regra e ficam separados do recall de antecipação. Reconhecer um atraso já ocorrido não é a mesma coisa que prevê-lo.''')
code('''# Inspecionamos as janelas e os rótulos disponíveis, sem ler resultados do teste final.
windows=[]
for start in DEV_STARTS:
    train,cal,cal_all,future=split_at(data,start,pd.Timestamp(start)+pd.DateOffset(months=1),TEST_START)
    windows.append(dict(inicio=start,treino_rotulo_conhecido=int((train.label_known_at<pd.Timestamp(start)).sum()),
        treino_ainda_censurado=int((train.delivered_at>=pd.Timestamp(start)).sum()),
        calibracao=len(cal),calibracao_sem_rotulo_excluida=len(cal_all)-len(cal),validacao_futura=len(future)))
display(pd.DataFrame(windows))''')
md('''## 5. Tecnologias e busca comparativa

Comparamos 55 configurações, cada uma nos quatro meses: **7 classificadores iniciais, 18 modelos de sobrevivência, 8 cascatas, 4 regressões de duração, 3 Random Forest com atributos derivados, 9 combinações entre modelos e 6 alternativas de maturação temporal**. São 220 comparações temporais. A busca é finita e reprodutível, com semente 42, quatro threads e configurações explícitas em `experiment.py` e `refinements.py`.

A pesquisa teve duas rodadas: a primeira comparou classificadores, AFT e cascatas; a segunda acrescentou regressão de duração e combinações, após observar que a primeira não resolvia satisfatoriamente o custo de alarmes. O mesmo critério e os mesmos quatro meses de desenvolvimento foram mantidos. A segunda rodada também deve ser considerada exploratória, pois o período histórico final já havia sido consultado.

- **Random Forest:** referência com os parâmetros da aplicação, reajustada sob o mesmo protocolo temporal dos candidatos.
- **CatBoost, LightGBM, XGBoost e HistGradientBoosting:** alternativas de árvores, algumas com maior peso para atrasos. Aqui usamos codificação One-Hot comum, inclusive no CatBoost, para manter a transformação compartilhada e auditável.
- **Regressão logística:** verificador simples com `StandardScaler` nos números; a escala evita que unidades muito grandes dominem esse modelo. Árvores não precisam desse escalonamento.
- **AFT:** aprende o tempo até entregar, em vez de somente sim/não. Testamos distribuições normal, logística e extrema, escalas 0,5/1/1,5 e profundidades 3/5. Entregas concluídas entram como duração exata; entregas futuras entram como intervalo `[tempo já observado, infinito]`. Somamos um dia às durações de calendário para evitar duração zero.
- **Calibração sigmoide:** transforma o score em uma estimativa de probabilidade no bloco passado reservado. Isso não garante calibração em uma operação futura.
- **Regressão de duração:** CatBoost estima dias de entrega com erro quadrático ou quantis 50/80/90; a folga entre duração prevista e prazo ordena o risco. Aqui só entram entregas efetivamente concluídas antes do ajuste, inclusive quando o rótulo binário de atraso já era conhecido antes da entrega.
- **Combinação de modelos:** combina os logits dos scores calibrados de RF/AFT, CatBoost/AFT ou RF/CatBoost, com pesos 25/75, 50/50 e 75/25. A ideia é aproveitar erros diferentes; os pesos são comparados apenas na validação.
- **Maturação temporal:** comparamos RF e CatBoost excluindo despachos dos últimos 35 ou 60 dias do ajuste, mantendo a calibração original; na terceira alternativa usamos calibração entre E−60 e E−35 e ajuste em despachos anteriores a E−60. Todos os rótulos usados precisam estar conhecidos em E. Isso testa o viés de incluir, entre os pedidos muito recentes, somente os que já tiveram uma resposta rápida. É uma alternativa de validação, não uma forma de fabricar rótulos para pedidos ainda abertos.

Não fazemos SMOTE nem duplicamos atrasos artificialmente. Não usamos overfitting como estratégia: decorar o treino melhora os números do passado e prejudica pedidos novos.''')
md('''## 6. Sua ideia: detector e revisor de falsos alertas

O primeiro detector busca aproximadamente **97,5% dos atrasos na calibração**. O segundo recebe somente alarmes históricos e aprende a distinguir atrasos reais de entregas pontuais que enganaram o detector.

Para montar esse material geramos previsões de agosto/2017 a abril/2018, treinando cada detector somente com o passado de cada mês. O revisor nunca aprende com o resultado do próprio detector nos pedidos usados para ajustar esse detector. Antes de cada ajuste do revisor, ainda exigimos que o rótulo estivesse conhecido naquela data e excluímos seu bloco de calibração.

O revisor recebe os atributos calculáveis do pedido, o score do detector e sua posição em relação aos negativos da calibração histórica. Negativos difíceis recebem mais peso, e atrasos reais também recebem peso alto para evitar descartá-los em excesso. Testamos regressão logística e LightGBM como revisores, com dois esquemas de peso cada, sobre dois detectores.

A decisão final exige passar pelos dois cortes. Um revisor também pode descartar atrasos verdadeiros; por isso mostramos **quantos falsos alarmes removeu e quantos atrasos perdeu**. A segunda etapa só merece ser escolhida se a validação mostrar vantagem pelo critério comum.''')
code('''# O cache só é aceito se dados e código de treinamento coincidirem.
sources=['data.py','features.py','runtime.py','experiment.py','refinements.py','evaluation.py']
signature=hashlib.sha256(b''.join((ROOT/'logipredict_final'/p).read_bytes() for p in sources)).hexdigest()
cache_ok=False
if (WORK/'run_signature.json').exists() and (WORK/'selection.joblib').exists():
    old=json.loads((WORK/'run_signature.json').read_text(encoding='utf-8'))
    old_manifest=json.loads((WORK/'data_manifest.json').read_text(encoding='utf-8'))
    cache_ok=old['source_sha256']==signature and old_manifest==manifest
if RETRAIN or not cache_ok:
    joblib.dump(data,WORK/'orders_clean.joblib')
    (WORK/'data_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    development,summary,oof=run_development(data,WORK)
    development,summary,oof=run_refinements(data,WORK)
    development,summary,oof=run_maturity(data,WORK)
    # Reexecutar o desenvolvimento também reexecuta a avaliação/exportação abaixo.
    cache_ok=False
else:
    saved=joblib.load(WORK/'selection.joblib')
    development,summary,oof=saved['records'],saved['summary'],saved['oof']
    print('Resultados calculados anteriormente com estes mesmos dados e fontes; cache validado.')
display(summary.reset_index().head(12))
print('Comparações temporais:',len(development),'| Configurações:',len(summary))''')
md('''## 7. Critério escolhido antes da avaliação final

O objetivo principal é buscar recall de **90% dos atrasos ainda não vencidos**. O corte de cada modelo é definido para atingir esse alvo na calibração passada. Depois medimos recall e taxa de falsos alertas no mês seguinte.

A nota por mês é `FPR + 5 × max(0, 0,90 − recall)`. FPR é a fração dos pedidos pontuais que receberam alarme. A nota final é a média mensal mais 0,25 vezes seu desvio padrão. Quanto menor, melhor. Esse peso dá prioridade explícita ao recall sem ignorar o custo dos alertas nem a instabilidade entre meses.

Também apresentamos perfis com alvos de 80% e 95%, definidos no mesmo bloco passado. **Alvo na calibração não é promessa de recall no teste.** Não ajustamos o corte olhando os erros finais.''')
code('''# Congelamos a escolha pela validação antes de abrir as métricas finais.
if RETRAIN or not cache_ok or not (WORK/'evaluation.joblib').exists():
    result=evaluate_selected(data,WORK)
else:
    result=joblib.load(WORK/'evaluation.joblib')
assert result['frozen']['primary']==summary.reset_index().iloc[0]['name']
display(Markdown('**Candidato escolhido na validação:** `'+result['frozen']['primary']+'`.'))
display(result['table'][['name','target','TP','TP_total','FP','FN','recall','recall_total','precision','ROC_AUC','AP','brier']])''')
md('''## 8. Como ler os resultados

**TP** é atraso antecipado corretamente. **TP_total** soma também os 132 pedidos que já estavam com prazo vencido no despacho. **FP** é um alarme sobre pedido que chegou no prazo. **FN** é atraso que passou sem alarme. Recall mede a fração dos atrasos encontrados; precisão mede quantos alarmes eram atrasos reais.

ROC-AUC e AP comparam a ordenação dos pedidos, mas não substituem a contagem no corte usado. Brier mede erro da estimativa probabilística (menor é melhor), mas também depende da frequência de atrasos. As métricas desta seção usam somente os pedidos que ainda podiam ser antecipados, exceto as colunas explicitamente marcadas como total.''')
code('''# Comparamos também os pesos efetivamente versionados na main, sem substituí-los.
main=compare_shipped_model(data,WORK)
display(pd.DataFrame([{'modelo':'Modelo original da main, corte original',**main['original_full_test']}]))
display(result['details'])
display(Markdown('Na tabela da cascata, `removed_false_alerts` é o ganho da revisão e `lost_true_late` é o preço pago em atrasos descartados, sempre comparando com seu detector de alta sensibilidade.'))''')
md('''## 9. O ganho é só por abaixar o corte?

Um modelo antigo também encontra mais atrasos se seu corte for reduzido. Para investigar melhoria de ordenação, calculamos abaixo quantos falsos alertas o modelo da main precisaria gerar para alcançar o mesmo recall de antecipação do candidato.

**Este diagnóstico usa o teste para localizar um corte equivalente. É um oráculo retrospectivo e não pode ser exportado como regra de produção.** Serve para não confundir aumento de sensibilidade com um algoritmo realmente melhor.''')
code('''display(pd.DataFrame(main['oracle_matching_recall_not_deployable']))
regions,budget,uncertainty=diagnostics(WORK)
display(Image(filename=str(WORK/'tradeoff.png')))
print('Diagnóstico de orçamento de 500 falsos alertas:',budget)
print('Diferenças pareadas e incerteza por semanas:',uncertainty)''')
md('''## 10. Regiões e mudança ao longo do tempo

Essas tabelas mostram onde o modelo erra mais; não ajustam o modelo usando o teste. Podem orientar os filtros futuros do mapa por UF, região e data. Cada pedido continua sendo uma observação: separar mapas não significa criar dados novos.

Uma região com poucos atrasos tem recall instável. As taxas observadas em 2018 não devem ser apresentadas como previsão garantida para 2026. O relatório por mês também ajuda a identificar mudança do padrão de entregas.''')
code('''display(regions)
display(pd.read_csv(WORK/'monthly_report.csv'))
train,cal,_,future=split_at(data,TEST_START,data.dispatched_at.max()+pd.Timedelta(seconds=1),TEST_START)
lo,hi=survival_bounds(train,TEST_START)
print('No ajuste final AFT: observações exatas =',int(np.isfinite(hi).sum()),'; censuradas =',int(np.isinf(hi).sum()))''')
md('''## 11. Exportação e testes de integração

O diretório `release` recebe os **mesmos pesos avaliados**, sem novo ajuste com os rótulos finais. O arquivo padrão usa o perfil de 90%. Outros arquivos preservam os perfis de 80% e 95%. Os metadados guardam origem, versões, entradas, corte, métricas e limitações.

Testamos: separação temporal, proibição de atributos de desfecho, preservação de censura ao alterar entregas futuras, decisões da cascata, igualdade antes/depois de salvar, entradas ausentes, validações HTTP e compatibilidade com o código real do serviço Python da main. Esses testes não substituem uma validação prospectiva com a operação da empresa.''')
code('''metadata=export_selected(WORK)
checks=verify(WORK)
print('Resumo em português:',write_report(WORK))
(WORK/'run_signature.json').write_text(json.dumps({'source_sha256':signature,'sources':sources},indent=2),encoding='utf-8')
display(pd.Series({k:(v['status'] if isinstance(v,dict) and 'status' in v else v) for k,v in checks.items()},name='Verificação'))
print('Modelo candidato:',metadata['version'])
print('Pasta:',ROOT/'release')
print('JSON de exemplo real:')
print((ROOT/'release/example_shipment.json').read_text(encoding='utf-8'))''')
md('''## 12. Preparação para o projeto final

A branch de integração se chama **main** no repositório consultado. Nada é enviado ao Git nem ativado na aplicação por este notebook.

O bundle mantém `pipeline.predict_proba(frame)` e `metadata.threshold`, formato já esperado pelo serviço existente. É necessário instalar o pacote `logipredict-final-candidate` no mesmo Python que carrega o Joblib, para que as classes personalizadas possam ser importadas. As versões completas estão no projeto e nos metadados.

Para homologar de forma isolada, na raiz do repositório, com a venv ativa:

```powershell
python -m pip install -e "ML/final_risk_training[research]"
$env:MODEL_DIR=(Resolve-Path "ML/final_risk_training/release").Path
python -m uvicorn logipredict_final.service:app --host 127.0.0.1 --port 8001
```

Em outro terminal, envie o exemplo real:

```powershell
$body=Get-Content "ML/final_risk_training/release/example_shipment.json" -Raw
Invoke-RestMethod -Uri "http://127.0.0.1:8001/predict" -Method Post -ContentType "application/json" -Body $body
```

O retorno mantém os campos que o Node já entende: `delay_probability`, `threshold`, `predicted_late`, `model_version`, `source`, `synthetic`, `warnings`. O serviço de homologação acrescenta `decision_source` para distinguir modelo de prazo já vencido. A API Node não precisa desse campo extra para funcionar.

Após homologar, a configuração `ML_URL=http://127.0.0.1:8001` pode direcionar o Node ao candidato, ou `MODEL_DIR` pode apontar o serviço Python existente para o bundle. Isso é uma etapa posterior de integração e não foi ativado automaticamente. O endpoint demonstrativo Node `/predict` de regras simples não é o serviço de ML nem o fluxo `/api/v1/predictions` usado pelo simulador.''')
code('''# Resumo calculado a partir dos resultados reais, sem números escritos à mão.
chosen=result['frozen']['primary']
rows=result['table'].loc[result['table'].name.eq(chosen)]
display(rows[['name','target','TP_total','FP','FN','recall_total','precision']])
primary=rows.loc[rows.target.eq(.9)].iloc[0]
old=main['original_full_test']
verdict=("**Nesta execução o candidato não reduziu os falsos alertas no diagnóstico de recall equivalente do perfil principal. "
         "A recomendação é preservar o modelo atual; o pacote exportado serve para pesquisa e homologação.**"
         if metadata['integration_recommendation'].startswith('retain_existing') else
         "A comparação é retrospectiva; qualquer promoção requer validação independente.")
display(Markdown(
    f"**Perfil principal:** {int(primary.TP_total)} dos 704 atrasos sinalizados, "
    f"{int(primary.FP)} falsos alertas e {int(primary.FN)} atrasos sem alarme. "
    f"Desses acertos, {int(primary.TP)} foram antecipações do modelo e 132 eram prazos já vencidos. "
    f"O modelo original da main, no seu corte original, sinalizou {old['TP']} atrasos e gerou {old['FP']} falsos alertas. "
    "Compare também a tabela de recall equivalente: encontrar mais atrasos, sozinho, não prova melhor ordenação. "+verdict
))''')
md('''## 13. O que ainda não podemos afirmar

- Não demonstramos um limite matemático do projeto. A busca testou configurações determinadas; outras entradas, cortes e modelos podem mudar a fronteira.
- Nenhuma cascata consegue recuperar atrasos que o primeiro detector descartou. A revisão pode reduzir alarmes e perder positivos; os dois efeitos precisam ser aceitos conscientemente.
- Os CSVs são históricos de 2016–2018 e esta coorte contém somente pedidos que foram entregues e passaram nos filtros. Não avaliamos cancelamentos nem a população completa de pedidos abertos de uma empresa atual.
- Embora os pesos e cortes desta execução sejam escolhidos sem as métricas finais, o período final já foi examinado em pesquisas anteriores. Para confirmar uma melhoria, precisamos de um período novo, sem reajustar após olhar seus erros, e depois monitoramento em operação.
- Dados de transportadora, eventos de rastreio, trânsito, clima e calendário municipal não estão disponíveis neste contrato. Não os simulamos.
- Mais recall geralmente traz mais alarmes. O ponto de operação deve refletir a capacidade da empresa de investigar alertas e o custo de deixar um atraso passar. Baixo risco nunca significa risco zero.

Referências técnicas: [XGBoost AFT e censura](https://xgboost.readthedocs.io/en/stable/tutorials/aft_survival_analysis.html), [scikit-learn: empilhamento e cuidado com previsões no próprio treino](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.StackingClassifier.html), [LightGBM e pesos das observações](https://lightgbm.readthedocs.io/en/stable/pythonapi/lightgbm.LGBMClassifier.html).''')
nb['cells']=cells
nb['metadata']={'kernelspec':{'display_name':'Python (LogiPredict .venv)','language':'python','name':'python3'},'language_info':{'name':'python','version':'3.12.10'}}
nbf.write(nb,root/'LogiPredict_Treinamento_Final.ipynb')
print('Notebook criado:',len(cells),'células')
