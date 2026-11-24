"""Amostragem somente do treino. Vetores SMOTENC nunca viram eventos históricos."""
from collections import Counter
import zlib
import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from imblearn.over_sampling import RandomOverSampler,SMOTENC
from imblearn.under_sampling import TomekLinks
from logipredict_final.features import FEATURES,NUMERIC,enrich,encoder

SEED=42
METHODS=[
    dict(name='controle',family='controle'),
    dict(name='duplicar_atrasos_2x',family='duplicacao'),
    dict(name='smotenc_atrasos_2x',family='sinteticos'),
    dict(name='smotenc_pontuais_125',family='sinteticos'),
    dict(name='reduzir_pontuais_50',family='eliminacao'),
    dict(name='manter_pontuais_dificeis_50',family='eliminacao'),
    dict(name='tomek_pontuais',family='eliminacao'),
    dict(name='repetir_falsos_alertas_dificeis',family='duplicacao'),
    dict(name='smotenc_atrasos_tomek',family='combinacao'),
]
DISCRETE=['items_count','sellers_count','remaining_days','purchase_month','dispatch_weekday',
          'interstate','promised_weekday','dispatch_weekend','promised_weekend','peak_month',
          'reference_alert','history_missing_seller','history_missing_zip']

def repair_generated(frame):
    """Recalcula relações disponíveis; não afirma que o rótulo artificial seja real."""
    out=frame.copy()
    for c in DISCRETE:
        if c in out:out[c]=pd.to_numeric(out[c],errors='raise').round()
    for c in NUMERIC:out[c]=pd.to_numeric(out[c],errors='raise')
    out['items_count']=out.items_count.clip(lower=1)
    out['sellers_count']=np.minimum(out.sellers_count.clip(lower=1),out.items_count)
    out['purchase_month']=out.purchase_month.clip(1,12)
    out['dispatch_weekday']=out.dispatch_weekday.clip(0,6)
    for c in ['distance_km','total_weight_g','total_volume_cm3','price','freight_value','dispatch_lead_days','remaining_days']:
        out[c]=out[c].clip(lower=0)
    if 'origin_prefix3' in out:
        out['route_prefix3']=out.origin_prefix3.astype(str)+'>'+out.destination_prefix3.astype(str)
    derived=enrich(out[FEATURES])
    for c in derived:out[c]=derived[c]
    for c in out:
        if c.startswith('h_') and '_count' in c:out[c]=pd.to_numeric(out[c]).round().clip(lower=0)
        if c.startswith('h_') and '_late_rate' in c:out[c]=pd.to_numeric(out[c]).clip(0,1)
    for group in ['global','seller','route','zip_route','destination']:
        for days in [30,90]:
            p50=f'h_{group}_p50_{days}';p90=f'h_{group}_p90_{days}';count=f'h_{group}_count{days}'
            out[p50]=pd.to_numeric(out[p50]).clip(lower=0)
            out[p90]=np.maximum(pd.to_numeric(out[p90]),out[p50])
            empty=out[count].eq(0)
            for c in [p50,p90,f'h_{group}_duration_mean{days}']:out.loc[empty,c]=np.nan
            for quantile in ['p50','p90']:
                out[f'h_{group}_slack_{quantile}_{days}']=out.remaining_days-out[f'h_{group}_{quantile}_{days}']
    # NaNs representam ausências legítimas; infinitos não são permitidos.
    assert not np.isinf(out.select_dtypes('number').to_numpy()).any()
    return out

def synthetic_rows(x,y,target,factor):
    """SMOTENC por par de UFs; categorías existentes, vizinhos só do treino."""
    cats=list(x.select_dtypes(include=['object','string']).columns)
    cats=list(dict.fromkeys(cats+[c for c in DISCRETE if c in x]))
    numbers=[c for c in x if c not in cats]
    imputer=SimpleImputer(strategy='median',keep_empty_features=True)
    scaler=StandardScaler()
    encoded=x.copy().reset_index(drop=True)
    encoded[numbers]=scaler.fit_transform(imputer.fit_transform(x[numbers]))
    for c in cats:encoded[c]=encoded[c].fillna('UNKNOWN').astype(str)
    generated=[];groups=[]
    for route,positions in encoded.groupby('route_state',sort=False).indices.items():
        positions=np.asarray(positions);yg=np.asarray(y)[positions];n=int((yg==target).sum())
        if n<2 or len(np.unique(yg))<2:
            groups.append(dict(route=str(route),input=len(positions),target=n,generated=0,reason='few_neighbors'))
            continue
        desired=max(n+1,int(np.ceil(n*factor)))
        seed=(SEED+zlib.crc32(str(route).encode()))%(2**32-1)
        sampler=SMOTENC(categorical_features=cats,sampling_strategy={target:desired},
                        k_neighbors=min(5,n-1),random_state=seed)
        xr,yr=sampler.fit_resample(encoded.iloc[positions],yg)
        extra=xr.iloc[len(positions):].copy()
        assert np.asarray(yr)[len(positions):].tolist()==[target]*len(extra)
        extra[numbers]=scaler.inverse_transform(extra[numbers])
        for c in DISCRETE:
            if c in extra:extra[c]=pd.to_numeric(extra[c])
        # SMOTENC escolhe valores categóricos presentes no treino da mesma rota.
        for c in x.select_dtypes(include=['object','string']):
            assert set(extra[c]).issubset(set(x.iloc[positions][c].fillna('UNKNOWN').astype(str)))
        generated.append(repair_generated(extra[x.columns]))
        groups.append(dict(route=str(route),input=len(positions),target=n,generated=len(extra),reason='generated'))
    if not generated:return x.iloc[:0].copy(),groups
    return pd.concat(generated,ignore_index=True),groups

def tomek_keep(x,y):
    """Remove apenas pontuais em pares de fronteira; preserva todos os atrasos."""
    prep=encoder(x,scale=True);z=prep.fit_transform(x)
    keep=np.ones(len(x),dtype=bool)
    # Vizinhança dentro da mesma rota de UFs reduz comparações incompatíveis.
    for _,positions in x.reset_index(drop=True).groupby('route_state',sort=False).indices.items():
        positions=np.asarray(positions);yg=np.asarray(y)[positions]
        if len(positions)<3 or len(np.unique(yg))<2:continue
        sampler=TomekLinks(sampling_strategy=[0],n_jobs=4)
        sampler.fit_resample(z[positions],yg)
        dropped=np.setdiff1d(np.arange(len(positions)),sampler.sample_indices_)
        assert (yg[dropped]==0).all()
        keep[positions[dropped]]=False
    return keep

def resample(x,y,method):
    y=np.asarray(y,dtype=int);rng=np.random.default_rng(SEED)
    original=len(x);synthetic=0;duplicates=0;removed=0;groups=[]
    name=method['name'];out=x.copy().reset_index(drop=True);labels=y.copy()
    if name=='duplicar_atrasos_2x':
        sampler=RandomOverSampler(sampling_strategy={1:int((y==1).sum())*2},random_state=SEED)
        out,labels=sampler.fit_resample(out,y);duplicates=len(out)-original
    elif name in ['smotenc_atrasos_2x','smotenc_pontuais_125','smotenc_atrasos_tomek']:
        target=0 if name=='smotenc_pontuais_125' else 1
        factor=1.25 if target==0 else 2.
        extra,groups=synthetic_rows(out,y,target,factor);synthetic=len(extra)
        out=pd.concat([out,extra],ignore_index=True);labels=np.r_[y,np.repeat(target,len(extra))]
    elif name in ['reduzir_pontuais_50','manter_pontuais_dificeis_50']:
        negative=np.flatnonzero(y==0);positive=np.flatnonzero(y==1);n=max(1,len(negative)//2)
        chosen=(rng.choice(negative,n,replace=False) if name=='reduzir_pontuais_50'
                else negative[np.argsort(out.reference_logit.to_numpy()[negative],kind='stable')[-n:]])
        index=np.sort(np.r_[positive,chosen]);out=out.iloc[index].copy();labels=y[index];removed=original-len(out)
    elif name=='repetir_falsos_alertas_dificeis':
        negative=np.flatnonzero(y==0);n=max(1,int(np.ceil(len(negative)*.25)))
        hard=negative[np.argsort(out.reference_logit.to_numpy()[negative],kind='stable')[-n:]]
        # O score é de uma previsão temporal fora do treino do detector.
        index=np.r_[np.arange(original),hard,hard]
        out=out.iloc[index].copy();labels=y[index];duplicates=len(out)-original
    elif name not in ['controle','tomek_pontuais']:raise KeyError(name)
    if name in ['tomek_pontuais','smotenc_atrasos_tomek']:
        keep=tomek_keep(out,labels);removed=int((~keep).sum());out=out.loc[keep];labels=labels[keep]
    out=out.reset_index(drop=True)
    assert set(labels)=={0,1} and len(out)==len(labels)
    audit=dict(method=name,input_rows=original,input_late=int((y==1).sum()),input_on_time=int((y==0).sum()),
        output_rows=len(out),output_late=int((labels==1).sum()),output_on_time=int((labels==0).sum()),
        synthetic_rows=synthetic,duplicated_rows=duplicates,removed_rows=removed,route_groups=groups)
    return out,np.asarray(labels,dtype=int),audit
