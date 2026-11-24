from pathlib import Path
import json
import joblib,numpy as np,pandas as pd
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator

def report(work):
    work=Path(work);r=joblib.load(work/'evaluation.joblib');t=r['table']
    nice={'preservado':'Modelo preservado','controle':'Controle sem amostragem',
        'duplicar_atrasos_2x':'Duplicação de atrasos','smotenc_atrasos_2x':'SMOTENC de atrasos',
        'smotenc_pontuais_125':'SMOTENC de pontuais','reduzir_pontuais_50':'Retirada aleatória de pontuais',
        'manter_pontuais_dificeis_50':'Manter pontuais difíceis','tomek_pontuais':'Limpeza Tomek de pontuais',
        'repetir_falsos_alertas_dificeis':'Repetir falsos alertas difíceis',
        'smotenc_atrasos_tomek':'SMOTENC + limpeza Tomek'}
    fig,axes=plt.subplots(1,2,figsize=(12,5))
    for ax,base in zip(axes,['base_564','base_613']):
        rows=t.loc[t.base.eq(base)]
        for i,(_,row) in enumerate(rows.iterrows()):
            ax.scatter(row.FP,row.TP,s=65,label=nice[row.method])
        ax.set(title=base.replace('base_','Referência '),xlabel='Falsos alertas',ylabel='Atrasos sinalizados (dos 704)')
        ax.yaxis.set_major_locator(MaxNLocator(integer=True))
        ax.grid(alpha=.2);ax.legend(fontsize=7);ax.margins(.2)
    fig.tight_layout();fig.savefig(work/'sampling_comparison.png',dpi=160);plt.close(fig)
    lines=['# Resultado: aumento artificial e redução de dados no treino','',
        'Preservamos os modelos de 564 acertos / 4.358 falsos alertas / 140 perdidos e de 613 acertos / 6.774 falsos alertas / 91 perdidos. Seus pesos e cortes não foram alterados.',
        '', 'Nove estratégias foram comparadas em quatro meses e duas referências: 72 avaliações temporais. Os detectores e o histórico real permaneceram fixos; somente o conjunto de ajuste do revisor mudou. Selecionamos estratégias por validação, incluindo a melhor de cada família para a comparação final.',
        '', '| Referência | Estratégia | Atrasos encontrados | Falsos alertas | Perdidos | Precisão | Recall | Acurácia |',
        '|---|---|---:|---:|---:|---:|---:|---:|']
    for _,row in t.iterrows():
        lines.append(f'| {row.base} | {nice[row.method]} | {int(row.TP)} | {int(row.FP)} | {int(row.FN)} | {row.precision:.2%} | {row.recall:.2%} | {row.accuracy:.2%} |')
    lines+=['','## Conclusão desta rodada','',
        'Os controles sem amostragem venceram o critério agregado de validação nas duas referências. Nenhuma estratégia nova demonstrou vantagem consistente entre os meses para substituir automaticamente os modelos preservados.']
    for base in ['base_564','base_613']:
        original=t.loc[t.base.eq(base)&t.method.eq('preservado')].iloc[0]
        better=t.loc[t.base.eq(base)&~t.method.isin(['preservado','controle'])&t.TP.ge(original.TP)&t.FP.lt(original.FP)]
        if better.empty:
            lines+=['',f'Em {base}, nenhum candidato avaliado no período final reduziu falsos alertas mantendo a quantidade de atrasos sinalizados.']
        else:
            row=better.sort_values('FP').iloc[0];drop=int(original.FP-row.FP)
            lines+=['',f'Em {base}, {nice[row.method]} teve ganho pontual: {int(row.TP)} acertos e {int(row.FP)} falsos alertas, redução líquida de {drop} ({drop/original.FP:.2%}). Perdeu {int(row.lost_TP)} caso(s) antes encontrado(s) e recuperou {int(row.recovered_TP)} outro(s); manter o total não significa preservar todos os mesmos pedidos. O ganho precisa de confirmação independente.']
    lines+=['','## Como avaliar o ganho','',
        'Aumentar a acurácia isoladamente não resolve o objetivo. Neste teste há 18.554 pedidos pontuais e 704 atrasados; dizer sempre “não atrasa” alcança 96,34% de acurácia e encontra zero atrasos. Por isso a seleção penaliza perder atrasos e compara a quantidade de falsos alertas com o controle.',
        '', 'O controle sem amostragem reproduz exatamente os dois modelos preservados. Calibração e teste mantiveram a proporção real de classes; nenhum pedido do teste foi apagado. Cortes são definidos no bloco passado real, não em dados artificiais e não pelos erros finais.',
        '', '## O que foi artificial','',
        'SMOTENC gera vetores de atributos próximos de exemplos de treino da mesma rota de UFs, usando categorias existentes. Padronização e imputação para vizinhança aprendem somente no treino. Recalculamos relações determinísticas disponíveis, arredondamos contagens e restringimos valores físicos. Os exemplos reais originais são preservados; os vetores novos são acrescentados somente ao ajuste.',
        '', 'Esses vetores não são pedidos realmente observados. Seus rótulos são hipóteses do método, e nem todas as relações operacionais podem ser garantidas. Eles não criam novas entregas reais, não alimentam o histórico de vendedor e não são importados na aplicação. Mais linhas não significa mais informação independente.',
        '', 'Duplicação reutiliza linhas reais. A mineração de falsos alertas usa previsões históricas fora do treino do detector. Retirada aleatória, seleção de pontuais difíceis e Tomek atuam somente no treino. As exclusões testadas preservam todos os exemplos reais de atraso dessa etapa.',
        '', '## Limitações e integração','',
        'O período final de 2018 já apareceu nas pesquisas anteriores. Os resultados são exploratórios, com semente 42, e não demonstram um limite absoluto nem confirmação independente. A população avaliada contém pedidos Olist posteriormente entregues e aprovados nos filtros.',
        '', 'A primeira etapa limita os acertos possíveis: a referência 564 não recupera atrasos descartados pelo seu detector. Na referência 613, o detector original ainda sinaliza até 614; reajustar o revisor pode recuperar um atraso perdido pelo filtro anterior.',
        '', 'Os modelos novos mantêm o contrato contextual com seller_id e prefixos CEP. O serviço deste pacote informa corretamente quando SMOTENC foi usado no treino; a geração artificial não roda na inferência. Nenhum modelo foi ativado na aplicação. Consulte README.md e o notebook.']
    path=work.parent/'RESULTADOS.md';path.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    return path

def paired_uncertainty(work):
    work=Path(work);r=joblib.load(work/'evaluation.joblib');b=joblib.load(work/'data.joblib')
    test=b['data'].loc[r['test_index']];weeks=test.dispatched_at.dt.to_period('W').astype(str).to_numpy();unique=np.unique(weeks)
    records=[];rng=np.random.default_rng(42)
    for label,p in r['scores'].items():
        row=r['table'].loc[(r['table'].base+'_'+r['table'].method).eq(label)].iloc[0]
        base=row.base;old_meta=json.loads((work.parent/'preservados'/base/'metadata.json').read_text(encoding='utf-8'))
        old=r['reference_scores'][base]>=old_meta['threshold'];new=p>=row.threshold;y=test.is_late.to_numpy()
        weekly=[]
        for week in unique:
            ix=weeks==week
            weekly.append([int(((new&~old)&(y==1)&ix).sum()-((old&~new)&(y==1)&ix).sum()),
                int(((new&~old)&(y==0)&ix).sum()-((old&~new)&(y==0)&ix).sum())])
        weekly=np.asarray(weekly)
        sampled=np.array([weekly[rng.integers(0,len(weekly),len(weekly))].sum(axis=0) for _ in range(1000)])
        ci=np.quantile(sampled,[.025,.975],axis=0)
        records.append(dict(model=label,delta_TP=int(weekly[:,0].sum()),delta_FP=int(weekly[:,1].sum()),
            delta_TP_low=ci[0,0],delta_TP_high=ci[1,0],delta_FP_low=ci[0,1],delta_FP_high=ci[1,1]))
    out=pd.DataFrame(records);out.to_csv(work/'paired_uncertainty.csv',index=False)
    return out
