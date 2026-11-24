from pathlib import Path
import json
import joblib,numpy as np,pandas as pd
import matplotlib.pyplot as plt

def report(work):
    work=Path(work);r=joblib.load(work/'final.joblib');table=r['results']
    labels={'referencia':'Referência preservada','rescore':'Reavaliação com contexto',
            'filter':'Filtro com contexto','double_review':'Contexto + revisão adicional'}
    fig,axes=plt.subplots(1,3,figsize=(14,4.5))
    for ax,ref in zip(axes,['modelo_631','modelo_564','modelo_614']):
        rows=table.loc[table.reference.eq(ref)]
        for _,row in rows.iterrows():
            markers={'referencia':'o','rescore':'^','filter':'s','double_review':'D'}
            ax.scatter(row.FP,row.TP,s=65,marker=markers[row.variant],label=labels[row.variant])
            offset={'referencia':(8,-22),'filter':(8,14),'rescore':(-8,-22),'double_review':(-8,14)}[row.variant]
            ax.annotate(f'{int(row.TP)} / {int(row.FP)}',(row.FP,row.TP),xytext=offset,
                textcoords='offset points',fontsize=8,ha='left' if offset[0]>0 else 'right',
                arrowprops={'arrowstyle':'-','lw':.5,'alpha':.5})
        ax.set(title=ref.replace('modelo_','Referência '),xlabel='Falsos alertas',ylabel='Atrasos sinalizados (dos 704)')
        ax.margins(x=.2,y=.2);ax.grid(alpha=.2);ax.legend(fontsize=7)
    fig.tight_layout();fig.savefig(work/'comparison.png',dpi=160);plt.close(fig)
    lines=['# Comparação final: contexto e revisão de alertas','',
        'As três referências foram preservadas com pesos, cortes, metadados e previsões em arquivos separados. O conjunto final contém 19.258 pedidos, 704 atrasos, dos quais 132 já estavam vencidos no despacho.',
        '', '| Referência | Variante | Atrasos sinalizados | Falsos alertas | Atrasos perdidos | Antecipados |',
        '|---|---|---:|---:|---:|---:|']
    for _,row in table.iterrows():
        lines.append(f'| {row.reference} | {labels[row.variant]} | {int(row.TP)} | {int(row.FP)} | {int(row.FN)} | {int(row.anticipated_TP)} |')
    lines+=['','## O que os filtros retiraram','',
        '| Modelo | Falsos alertas removidos | Atrasos reais descartados |',
        '|---|---:|---:|']
    for _,row in table.loc[table.variant.isin(['filter','double_review'])].iterrows():
        lines.append(f'| {row["name"]} | {int(row.removed_FP)} | {int(row.lost_TP)} |')
    lines+=['','## Perfis adicionais do filtro 614','',
        '| Retenção alvo na calibração | Atrasos sinalizados | Falsos alertas | Perdidos |',
        '|---|---:|---:|---:|']
    extra=r['retentions'].loc[r['retentions'].name.eq('modelo_614_filter')&r['retentions'].calibration_retention.isin([.975,.95])]
    for _,row in extra.iterrows():
        lines.append(f'| {row.calibration_retention:.1%} | {int(row.TP)} | {int(row.FP)} | {int(row.FN)} |')
    lines+=['','A revisão adicional do modelo 614 é comparada à sua versão já enriquecida, não diretamente à referência original. O filtro simples de 614 é comparado à referência original. Filtros não podem recuperar pedidos que sua etapa anterior descartou.',
        '', '## Critério e dados','',
        'As quatro configurações de revisor são comparadas em dezembro/2017 e fevereiro, março e abril/2018. A reavaliação procura reduzir FPR penalizando perda de recall em relação à referência. O filtro procura reduzir a proporção de falsos alertas e penaliza retenção abaixo de 98% dos atrasos da referência. O perfil principal procura preservar 99% dos acertos no bloco de calibração passado; isso não garante retenção igual no teste.',
        '', 'Os revisores aprendem com previsões de réplicas históricas feitas antes do período previsto, excluindo o bloco de calibração e rótulos ainda desconhecidos. A terceira etapa recebe previsões temporais do próprio modelo enriquecido, sem treinar sobre seus acertos no próprio ajuste.',
        '', 'O contexto usa somente entregas concluídas antes do despacho: histórico global, vendedor principal, par de UFs, rota por prefixos de CEP de três dígitos e destino. Calculamos contagens, taxas de atraso suavizadas, duração média, P50/P90 e folga do prazo, em janelas de 30/90 dias e histórico acumulado. A suavização usa a taxa global anterior ao pedido, com força fixa 20; não cria pedidos ou desfechos.',
        '', '## Como interpretar a atualização do histórico','',
        'A comparação principal simula o histórico sendo atualizado conforme entregas anteriores ocorrem durante o teste. Nenhum evento na hora da previsão ou depois dela pode ser usado. Pesos e cortes permanecem fixos. O relatório controls.csv também mostra o resultado com histórico congelado no início do teste e o controle sem atributos históricos.',
        '', 'É uma comparação retrospectiva com Olist 2016–2018; o mesmo período final já foi examinado antes. Não é uma confirmação independente nem prova de qualidade máxima. A população contém apenas pedidos posteriormente entregues e aprovados nos filtros. O histórico do vendedor é do vendedor principal; pedidos com vários vendedores não têm seus pacotes individualizados.',
        '', '## Integração','',
        'Os novos modelos exigem serviço que receba datas originais e seller_id, origin_prefix5 e destination_prefix5. A aplicação atual não fornece todos esses campos ao modelo. O serviço de homologação oferecido preserva a previsão da referência quando faltam essas identidades, com aviso explícito. Os resultados enriquecidos não devem ser prometidos para entradas sem esses campos.',
        '', 'Nenhuma versão foi ativada na aplicação e nenhum arquivo anterior foi substituído. README.md explica execução e homologação. O notebook contém os resultados, os controles e os testes.']
    path=work.parent/'RESULTADOS.md';path.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    return path
