from pathlib import Path
import nbformat as n
root=Path(__file__).resolve().parent;nb=n.v4.new_notebook();cells=[]
def md(s):cells.append(n.v4.new_markdown_cell(s.strip()))
def code(s):cells.append(n.v4.new_code_cell(s.strip()))
md('''# Teste de aumento artificial e limpeza de dados de treino

Preservamos duas referências: **564 atrasos encontrados / 4.358 falsos alertas / 140 perdidos** e **613 encontrados / 6.774 falsos alertas / 91 perdidos**. A segunda é a versão do modelo de 614 com filtro mais restritivo.

Queremos saber se aumentar, repetir ou retirar exemplos do treino melhora o equilíbrio entre encontrar atrasos reais e evitar alertas falsos. **Calibração e teste continuam reais e completos.** Não apagamos erros da avaliação para melhorar números.

O estudo é exploratório: esse período histórico já foi consultado em pesquisas anteriores. Não é prova de um limite máximo, nem confirmação independente para uma operação atual.''')
md('''## 1. Ambiente e referências preservadas

Pandas/NumPy organizam os dados. Imbalanced-learn fornece RandomOverSampler, SMOTENC e TomekLinks. Scikit-learn fornece imputação e escala para vizinhança. Mantemos o CatBoost de 350 árvores e profundidade 6 dos dois revisores, para isolar o efeito da amostragem.

Na raiz do repositório:

```powershell
.\\.venv\\Scripts\\python.exe -m pip install -e "ML/final_risk_training[research]"
.\\.venv\\Scripts\\python.exe -m pip install -e "ML/context_review_comparison[research]"
.\\.venv\\Scripts\\python.exe -m pip install -e "ML/sampling_comparison[research]"
```

Selecione o Python dessa venv como kernel. O ZIP inclui os pacotes anteriores em `runtime_final` e `runtime_context`, para instalar primeiro quando estiver fora do repositório.''')
code('''import os
for key in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS']:
    os.environ[key]='4'
from pathlib import Path
import json,hashlib,joblib
import pandas as pd
import numpy as np
from IPython.display import display,Image,Markdown
import sampling_risk
from sampling_risk.study import load_data,run_development
from sampling_risk.resampling import METHODS,resample
from sampling_risk.evaluate import evaluate_final,export_models
from sampling_risk.checks import verify
from sampling_risk.reporting import report,paired_uncertainty
ROOT=Path(sampling_risk.__file__).resolve().parents[1]
WORK=ROOT/'artifacts';WORK.mkdir(exist_ok=True)
RETRAIN=False  # True refaz os novos ajustes; as cópias preservadas não são substituídas.
references=[]
for base in ['base_564','base_613']:
    metadata=json.loads((ROOT/'preservados'/base/'metadata.json').read_text(encoding='utf-8'))
    references.append({'modelo':base,**metadata['metrics']})
display(pd.DataFrame(references)[['modelo','TP','FP','FN','precision','recall']])''')
md('''## 2. O que muda e o que limita o ganho

Os detectores anteriores permanecem congelados. Ajustamos novamente somente os revisores contextuais que decidem quais alertas manter. Isso preserva os pesos antigos para comparação e evita inventar datas de entrega para reajustar o modelo de duração.

A primeira etapa limita os acertos: o detector da referência 564 sinaliza até 564 atrasos nesta coorte. O detector anterior ao filtro de 613 sinaliza até 614; um revisor novo pode recuperar o atraso que o filtro antigo descartou, mas não os atrasos descartados pelo detector.

Os dados continuam sendo a mesma Olist de 2016–2018. O histórico de vendedor/rota usa somente entregas concluídas antes de cada despacho. **Os vetores sintéticos não entram nesse histórico.**''')
code('''bundle=joblib.load(WORK/'data.joblib') if (WORK/'data.joblib').exists() else load_data(ROOT)
# Revalidamos a origem dos CSVs antes de usar o cache de resultados.
from logipredict_final.data import load_orders
data_check,manifest=load_orders()
assert bundle['manifest']==manifest
assert data_check.order_id.tolist()==bundle['data'].order_id.tolist()
data,context=bundle['data'],bundle['context']
oof=joblib.load(ROOT/'training_inputs/oof.joblib')
display(pd.Series(manifest['quality']))
display(pd.DataFrame(METHODS))
print('Teste real: 19.258 pedidos; 704 atrasos. Nenhuma amostragem será aplicada nele.')''')
md('''## 3. Nove estratégias

- **Controle:** mesmos exemplos e parâmetros do revisor anterior. Precisa reproduzir exatamente os modelos preservados na avaliação final.
- **Duplicar atrasos:** aumenta a frequência de exemplos reais de atraso, sem criar informação nova.
- **SMOTENC de atrasos:** cria vetores próximos de atrasos reais no espaço de atributos.
- **SMOTENC de pontuais:** aumenta exemplos hipotéticos de entregas pontuais, para investigar redução de falsos alertas.
- **Retirada aleatória:** mantém todos os atrasos e metade dos pontuais do treino.
- **Manter pontuais difíceis:** mantém os atrasos e a metade dos pontuais com maior score histórico do detector. São os exemplos que mais se parecem com atrasos para a primeira etapa.
- **Tomek de pontuais:** procura pares vizinhos de classes diferentes e remove somente os pontuais de fronteira. Isso pode ajudar ou prejudicar; remover pontuais também pode aumentar alarmes.
- **Repetir falsos alertas difíceis:** triplica a presença do quarto mais difícil dos pontuais, mantendo todos os outros exemplos.
- **SMOTENC + Tomek:** combina geração de atrasos e limpeza de pontuais.

Nenhum método elimina atrasos reais do ajuste. As estratégias de exclusão não tocam a calibração nem o teste.''')
md('''## 4. Como foram gerados os exemplos artificiais

SMOTENC utiliza vizinhos e categorias existentes. Geramos dentro do mesmo par de UFs; grupos com menos de dois exemplos da classe desejada são ignorados. Medianas e StandardScaler são aprendidos somente nos números do treino para que quilogramas, quilômetros e taxas não tenham influência arbitrária na vizinhança.

Mantemos os exemplos reais originais com seus valores e ausências. Só os novos vetores recebem a transformação inversa. Recalculamos proporções físicas, rotas de prefixos, dias da semana derivados e folgas de prazo; arredondamos contagens, limitamos taxas a [0,1] e preservamos vendedores ≤ itens e P50 ≤ P90.

**Ainda assim, são vetores hipotéticos de treinamento.** Não há uma entrega observada que comprove seu rótulo. Nem todas as relações entre atributos podem ser garantidas, inclusive a relação entre o score antigo interpolado e um pedido físico. O teste real é necessário para descobrir se essas aproximações ajudam ou apenas introduzem ruído.

Não usamos texto gerado por IA, datas de entrega inventadas ou pedidos artificiais importados na aplicação.''')
code('''# Exemplo de auditoria com um pequeno treino histórico real, sem usar o teste final.
from context_risk.study import pool_for
x,y=pool_for(data,context,oof['records'],'modelo_564','2017-12-01','filter',True)
demo=[]
for method in METHODS:
    _,_,audit=resample(x,y,method)
    demo.append({k:v for k,v in audit.items() if k!='route_groups'})
display(pd.DataFrame(demo)[['method','input_rows','output_rows','synthetic_rows','duplicated_rows','removed_rows']])''')
md('''## 5. Validação temporal e escolha

São quatro meses futuros de validação por referência: dezembro/2017 e fevereiro, março e abril/2018. O revisor aprende com previsões históricas fora do ajuste do detector, com despacho anterior ao bloco de calibração e rótulo disponível antes do ajuste.

Cada transformação é ajustada novamente somente no treino daquela janela. Os vizinhos do SMOTENC/Tomek não podem enxergar calibração ou teste. A seleção usa 72 avaliações: 9 estratégias × 4 meses × 2 referências.

O corte procura preservar 99% dos atrasos identificados pelo detector na calibração da referência 564 e 95% na referência 613, como nas versões preservadas. O bloco de calibração é real. Mudanças de frequência de classes no treino não justificam usar o mesmo corte numérico automaticamente.

A nota mensal é `FP_ratio + 20 × max(0, 0,99 − retenção_de_TP)`, relativa ao controle sem amostragem. Acrescentamos 0,25 vezes o desvio entre meses. Quanto menor, melhor. A escolha é congelada antes dos novos resultados finais; comparamos também o melhor de cada família. A semente é 42. As referências podem ser executadas em paralelo, com quatro threads por ajuste.''')
code('''files=['resampling.py','study.py','evaluate.py']
signature=hashlib.sha256(b''.join((ROOT/'sampling_risk'/f).read_bytes() for f in files)).hexdigest()
if RETRAIN:
    bundle=load_data(ROOT);joblib.dump(bundle,WORK/'data.joblib',compress=3)
    run_development(bundle,oof,WORK)
else:
    saved=json.loads((WORK/'signature.json').read_text(encoding='utf-8'))
    assert saved['source_sha256']==signature,'Código mudou: refaça explicitamente os novos treinos.'
selection=joblib.load(WORK/'selection.joblib')
display(selection['summary'].reset_index())
display(selection['frozen'])''')
md('''## 6. Resultado em pedidos reais

TP é atraso sinalizado corretamente; FP é pedido pontual que recebeu alarme; FN é atraso perdido. Precisão mede quantos alarmes estavam certos; recall mede a fração dos atrasos encontrados.

Os totais incluem prazos já vencidos no despacho. A tabela separa os acertos antecipados desses casos. A RF original sinaliza 130 casos já vencidos; o detector da família 613 sinaliza 132. Não atribuímos essa regra ao aprendizado novo.''')
code('''result=evaluate_final(bundle,oof,WORK) if RETRAIN else joblib.load(WORK/'evaluation.joblib')
display(result['table'][['base','method','TP','FP','FN','precision','recall','accuracy','anticipated_TP','known_overdue_TP']])
display(result['table'][['base','method','removed_FP','lost_TP','recovered_TP','added_FP']])
report(WORK)
display(Image(filename=str(WORK/'sampling_comparison.png')))''')
md('''## 7. Acurácia e incerteza

Neste teste, 18.554 pedidos são pontuais. Um sistema que responda sempre “não atrasa” alcança **96,34% de acurácia e encontra zero atrasos**. Por isso, maior acurácia sozinha não demonstra melhor avaliação de risco.

Abaixo reamostramos semanas para estimar a variação das diferenças de TP e FP em relação às referências, sem treinar novamente. Isso não corrige o reaproveitamento histórico do período, nem substitui confirmação em uma amostra nova. Só usamos uma semente de treinamento nesta rodada.''')
code('''display(paired_uncertainty(WORK))
audits=[]
for label,audit in result['audits'].items():
    audits.append({'model':label,**{k:v for k,v in audit.items() if k!='route_groups'}})
display(pd.DataFrame(audits)[['model','input_rows','output_rows','synthetic_rows','duplicated_rows','removed_rows']])''')
md('''## 8. Exportação e verificações

Os dois originais continuam em `preservados`, com pesos e cortes idênticos. Os candidatos ficam em `modelos_novos`. Cada metadado registra quantos exemplos foram reais, sintéticos, repetidos ou removidos, além de versões e métricas.

Testamos determinismo, preservação dos exemplos originais, limites dos vetores gerados, exclusão do teste das fontes de amostragem, equivalência do controle, histórico sem eventos artificiais, serialização e sinalização HTTP de treinamento aumentado.

A geração artificial não roda na previsão. Os modelos continuam exigindo a integração contextual de vendedor e CEP; sem essas informações, o serviço usa somente a etapa original e avisa. Nenhuma versão é ativada no Node/Flutter por este notebook.''')
code('''print('Exportados em:',export_models(WORK))
checks=verify(WORK)
display(pd.Series(checks))
print('Relatório:',report(WORK))
(WORK/'signature.json').write_text(json.dumps({'files':files,'source_sha256':signature},indent=2),encoding='utf-8')''')
md('''O serviço de homologação deste pacote informa quando o revisor usou SMOTENC no treino:

```powershell
$env:MODEL_DIR=(Resolve-Path "ML/sampling_comparison/modelos_novos/NOME_DO_MODELO").Path
python -m uvicorn sampling_risk.service:app --host 127.0.0.1 --port 8003
```

O JSON `exemplo_real.json` é um pedido real; os vetores sintéticos de treino não devem ser enviados como se fossem pedidos reais. Os pesos continuam experimentais e não foram ativados na aplicação.

Fontes técnicas: [aumento de amostras e SMOTENC](https://imbalanced-learn.org/stable/over_sampling.html), [redução e limpeza Tomek](https://imbalanced-learn.org/stable/under_sampling.html), [risco de vazamento ao reamostrar antes de separar os dados](https://imbalanced-learn.org/stable/common_pitfalls.html).''')
nb.cells=cells;nb.metadata={'kernelspec':{'name':'python3','display_name':'Python LogiPredict .venv','language':'python'},'language_info':{'name':'python','version':'3.12.10'}}
n.write(nb,root/'Teste_Amostragem_Artificial_e_Limpeza.ipynb')
print('Notebook montado:',len(cells),'células')
