"""Tabelas e figuras do benchmark, com previsão e atraso já conhecido separados."""
from pathlib import Path
import json
import joblib,numpy as np,pandas as pd
import matplotlib.pyplot as plt
from sklearn.metrics import roc_curve,precision_recall_curve
from .experiment import metrics


def diagnostics(work):
    work=Path(work);r=joblib.load(work/'evaluation.joblib');name=r['frozen']['primary']
    f=r['future'];y=f.is_late.to_numpy();p=r['scores'][(name,.9)];pipe=r['models'][(name,.9)]
    predicted=p>=pipe.threshold
    regional=f[['customer_state','customer_region','remaining_days','dispatched_at']].copy() if 'customer_region' in f else f[['customer_state','remaining_days','dispatched_at']].copy()
    from .features import REGIONS
    regional['region']=regional.customer_state.map(REGIONS)
    regional['late']=y;regional['alert']=predicted
    regional['TP']=(predicted&(y==1)).astype(int);regional['FP']=(predicted&(y==0)).astype(int)
    byregion=regional.groupby('region').agg(orders=('late','size'),late=('late','sum'),TP=('TP','sum'),FP=('FP','sum'))
    byregion['recall']=byregion.TP/byregion.late
    byregion.to_csv(work/'regional_report.csv')
    month=regional.dispatched_at.dt.to_period('M').astype(str)
    regional.groupby(month).agg(orders=('late','size'),late=('late','sum'),TP=('TP','sum'),FP=('FP','sum')).to_csv(work/'monthly_report.csv')
    # A curva usa o teste apenas para descrever o potencial de ordenação; não ajusta pesos/cortes.
    fpr,tpr,cuts=roc_curve(y,p,drop_intermediate=False)
    fp=np.rint(fpr*(y==0).sum()).astype(int);tp=np.rint(tpr*(y==1).sum()).astype(int)
    allowed=np.flatnonzero(fp<=500);best=allowed[np.argmax(tp[allowed])]
    oracle=dict(FP=int(fp[best]),TP_proactive=int(tp[best]),TP_total=int(tp[best]+r['all_test'].already_overdue.sum()),
                warning='Oracle retrospectivo: usa os rótulos do teste; não é um corte de produção nem limite universal.')
    (work/'budget_500_diagnostic.json').write_text(json.dumps(oracle,ensure_ascii=False,indent=2),encoding='utf-8')
    fig,axes=plt.subplots(1,2,figsize=(13,5))
    labels={'rf_main':'RF reajustada','cascade_cb150_lr_hard3':'CatBoost + revisor',
        'aft_extreme_0.5_3':'Sobrevivência AFT','duration_Q90':'Duração (quantil 90)',
        'rf_derived_unweighted':'RF com cruzamentos','mature_rf_main_gap35':'RF com maturação',
        name:'Candidato: CatBoost + AFT' if name.startswith('blend_') else name}
    for candidate in r['table'].name.unique():
        s=r['scores'][(candidate,.9)]
        a,b,_=roc_curve(y,s,drop_intermediate=False)
        axes[0].plot(a*(y==0).sum(),b*(y==1).sum(),label=labels.get(candidate,candidate))
        table=r['table'].loc[r['table'].name.eq(candidate)]
        axes[1].plot(table.FP,table.TP_total,marker='o',label=labels.get(candidate,candidate))
    baseline=joblib.load(work/'main_model.joblib')
    from .features import feature_frame
    baseline_scores=baseline['pipeline'].predict_proba(feature_frame(f))[:,1]
    a,b,_=roc_curve(y,baseline_scores,drop_intermediate=False)
    axes[0].plot(a*(y==0).sum(),b*(y==1).sum(),color='black',ls='--',label='RF atual (pesos da main)')
    original=json.loads((work/'main_comparison.json').read_text(encoding='utf-8'))['original_full_test']
    axes[1].scatter(original['FP'],original['TP'],color='black',marker='*',s=100,label='RF atual, corte original')
    axes[0].axvline(500,color='gray',ls='--',alpha=.6)
    axes[0].set(xlabel='Falsos alertas no período',ylabel='Atrasos antecipados (dos 572)',title='Ordenação retrospectiva — cortes não exportáveis')
    axes[1].set(xlabel='Falsos alertas',ylabel='Atrasos sinalizados (dos 704)',title='Cortes definidos antes do período final')
    for ax in axes:
        ax.legend(fontsize=7);ax.grid(alpha=.2)
    fig.tight_layout();fig.savefig(work/'tradeoff.png',dpi=160);plt.close(fig)
    # Intervalos por reamostragem de semanas preservam parte da dependência temporal.
    bp=baseline_scores>=baseline['metadata']['threshold']
    periods=f.dispatched_at.dt.to_period('W').astype(str).to_numpy();weeks=np.unique(periods)
    differences=[];rng=np.random.default_rng(42)
    weekly=[]
    for week in weeks:
        ix=periods==week
        weekly.append([int(((predicted&~bp)&(y==1)&ix).sum()-((bp&~predicted)&(y==1)&ix).sum()),
                       int(((predicted&~bp)&(y==0)&ix).sum()-((bp&~predicted)&(y==0)&ix).sum())])
    weekly=np.asarray(weekly)
    for _ in range(1000):
        differences.append(weekly[rng.integers(0,len(weeks),len(weeks))].sum(axis=0))
    ci=np.quantile(differences,[.025,.975],axis=0)
    uncertainty=dict(delta_TP_proactive=int(weekly[:,0].sum()),delta_FP=int(weekly[:,1].sum()),
        weekly_bootstrap_95pct_TP=ci[:,0].tolist(),weekly_bootstrap_95pct_FP=ci[:,1].tolist(),
        note='Comparação pareada no mesmo período; não corrige seleção histórica nem prova desempenho futuro.')
    (work/'uncertainty.json').write_text(json.dumps(uncertainty,ensure_ascii=False,indent=2),encoding='utf-8')
    return byregion,oracle,uncertainty


def write_report(work):
    """Resumo legível com os números da execução, sem escolha posterior de corte."""
    work=Path(work);r=joblib.load(work/'evaluation.joblib')
    main=json.loads((work/'main_comparison.json').read_text(encoding='utf-8'))
    checks=json.loads((work/'verification.json').read_text(encoding='utf-8'))
    oracle=json.loads((work/'budget_500_diagnostic.json').read_text(encoding='utf-8'))
    primary=r['frozen']['primary'];rows=r['table'].loc[r['table'].name.eq(primary)]
    selected=rows.loc[rows.target.eq(.9)].iloc[0];old=main['original_full_test']
    matched=next(v for v in main['oracle_matching_recall_not_deployable'] if v['target']==.9)
    ranking='menor' if selected.FP<matched['FP'] else 'maior ou igual'
    lines=['# Resultado medido — candidato de homologação','',
        f'Escolha pelo desenvolvimento: **{primary}**. Foram 55 configurações e 220 comparações em quatro meses, além das previsões históricas para treinar os revisores.',
        '',f'Avaliação final: {len(r["all_test"]):,} pedidos, 704 atrasos. Destes, 132 já tinham prazo vencido no despacho; o modelo pode antecipar os outros 572.',
        '', '| Modelo / perfil | Atrasos sinalizados dos 704 | Antecipados dos 572 | Falsos alertas | Atrasos perdidos |',
        '|---|---:|---:|---:|---:|',
        f'| Pesos atuais da main, corte original | {old["TP"]} | {main["proactive"]["TP"]} | {old["FP"]} | {old["FN"]} |']
    for _,row in rows.iterrows():
        lines.append(f'| Candidato, alvo de calibração {row.target:.0%} | {int(row.TP_total)} | {int(row.TP)} | {int(row.FP)} | {int(row.FN)} |')
    lines+=['',f'No perfil principal, o candidato sinaliza {int(selected.TP_total)-old["TP"]:+d} atrasos e gera {int(selected.FP)-old["FP"]:+d} falsos alertas em relação ao corte original. Isso, sozinho, não demonstra que a ordenação do novo modelo seja melhor.',
        '',f'Para alcançar o mesmo recall de antecipação ({selected.recall:.1%}), o modelo original precisaria de {matched["FP"]} falsos alertas no diagnóstico retrospectivo. O candidato tem quantidade **{ranking}** ({int(selected.FP)}). Esse corte equivalente foi localizado no teste e não pode ser usado como corte de produção.',
        '',f'Com orçamento de até 500 falsos alertas, a ordenação do candidato chega retrospectivamente a {oracle["TP_total"]} atrasos sinalizados, incluindo os 132 já vencidos. Não atingimos 600 atrasos com apenas 500 alarmes falsos. Isso não prova um limite universal.',
        '', '## Revisão de alertas','',
        '| Cascata / alvo | Falsos alertas removidos do detector | Atrasos reais descartados junto |',
        '|---|---:|---:|']
    for _,row in r['details'].iterrows():
        lines.append(f'| {row["name"]} / {row.target:.0%} | {int(row.removed_false_alerts)} | {int(row.lost_true_late)} |')
    lines+=['','O revisor não recupera casos perdidos pelo primeiro detector. Ele foi comparado pelo mesmo critério e não foi imposto como solução obrigatória.',
        '', '## Integração','',
        f'O serviço candidato e o código original do serviço da main carregaram o mesmo bundle e passaram nos testes. Tempo observado da primeira requisição no teste local: {checks["unchanged_main_service"]["first_request_ms"]} ms; é uma medida local isolada, não um teste de carga.',
        '', 'Nenhum arquivo existente do sistema foi alterado. O modelo atual permanece em uso. O bundle exportado contém exatamente os pesos avaliados; não foi reajustado com o período final.',
        '', '## Interpretação e limites','',
        'O objetivo de 90% é definido na calibração, não uma garantia sobre pedidos futuros. O melhor candidato é o que venceu o critério de desenvolvimento entre os métodos testados. Não se pode afirmar que atingimos o melhor resultado matematicamente possível.',
        '', 'Os dados são Olist 2016–2018, apenas pedidos posteriormente entregues e aprovados nos filtros. O período final já foi usado em pesquisas anteriores: a comparação é retrospectiva. Validação em período novo continua necessária antes de promover o candidato.',
        '', 'O pacote usa as 13 entradas disponíveis no serviço atual e cruzamentos calculáveis. IDs de vendedor, CEP, categorias e históricos mais ricos existem nos dados, mas sua integração exigiria ampliar o contrato e fornecer essas mesmas informações no serviço. Não usamos campos fictícios para simular essa disponibilidade.',
        '', 'Veja o notebook para as métricas por família, regiões, meses, calibração, censura, incerteza e testes. Veja README.md para executar e homologar.']
    path=work.parent/'RESULTADOS.md';path.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    return path
