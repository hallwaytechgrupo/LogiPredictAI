"""Histórico consultado no instante do despacho; nenhuma entrega futura é lida."""
from dataclasses import dataclass
from bisect import bisect_left,insort
from collections import deque
import numpy as np
import pandas as pd

DAY=86400e9
GROUPS=[('global_key','global'),('seller_id','seller'),('route_state','route'),
        ('route_prefix3','zip_route'),('destination_prefix3','destination')]

def identities(rows):
    out=pd.DataFrame(index=rows.index)
    for c in ['seller_id','origin_prefix5','destination_prefix5']:
        value=rows[c] if c in rows else pd.Series(None,index=rows.index,dtype=object)
        out[c]=value.fillna('UNKNOWN').astype(str)
    for c in ['origin_prefix5','destination_prefix5']:
        valid=out[c].str.fullmatch(r'\d{1,5}')
        out.loc[valid,c]=out.loc[valid,c].str.zfill(5)
        out[c.replace('5','3')]=out[c].str[:3].where(valid,'UNKNOWN')
    out['route_state']=rows.seller_state.astype(str)+'>'+rows.customer_state.astype(str)
    out['route_prefix3']=out.origin_prefix3+'>'+out.destination_prefix3
    out['global_key']='ALL'
    return out

def quantile(values,q):
    if not values:return np.nan
    at=(len(values)-1)*q;lo=int(at);hi=min(lo+1,len(values)-1)
    return values[lo]+(values[hi]-values[lo])*(at-lo)

def group_statistics(queries,events,key,prefix):
    """Janelas exatas [despacho−30/90 dias, despacho), inclusive em empates."""
    columns=['count','late_sum','duration_mean']
    for days in [30,90]:columns += [f'count{days}',f'late_sum{days}',f'duration_mean{days}',f'p50_{days}',f'p90_{days}']
    output=np.full((len(queries),len(columns)),np.nan)
    # Em uma requisição não agrupamos todos os vendedores/rotas da base.
    relevant=events.loc[events[key].isin(queries[key].unique())]
    event_groups={str(k):g.sort_values('delivered_at',kind='stable') for k,g in relevant.groupby(key,sort=False)}
    for value,query in queries.groupby(key,sort=False):
        ev=event_groups.get(str(value))
        if ev is None:
            output[np.ix_(query._position.to_numpy(),[0,1,3,4,8,9])]=0
            continue
        times=ev.delivered_at.astype('int64').to_numpy();late=ev.is_late.to_numpy();duration=ev.duration.to_numpy()
        if len(query)<64:
            cs_late=np.r_[0,np.cumsum(late)];cs_duration=np.r_[0,np.cumsum(duration)]
            for query_time,position in query[['query_time','_position']].itertuples(index=False,name=None):
                instant=pd.Timestamp(query_time).value;hi=np.searchsorted(times,instant,side='left')
                values=[hi,cs_late[hi],cs_duration[hi]/hi if hi else np.nan]
                for days in [30,90]:
                    lo=np.searchsorted(times,instant-days*DAY,side='left');n=hi-lo
                    qs=np.quantile(duration[lo:hi],[.5,.9]) if n else [np.nan,np.nan]
                    values += [n,cs_late[hi]-cs_late[lo],(cs_duration[hi]-cs_duration[lo])/n if n else np.nan,*qs]
                output[int(position)]=values
            continue
        pointer=0;count=0;late_total=0.;duration_total=0.
        windows={days:dict(queue=deque(),sorted=[],late=0.,duration=0.) for days in [30,90]}
        for query_time,position in query.sort_values('query_time',kind='stable')[['query_time','_position']].itertuples(index=False,name=None):
            instant=pd.Timestamp(query_time).value
            while pointer<len(times) and times[pointer]<instant:
                count+=1;late_total+=late[pointer];duration_total+=duration[pointer]
                for state in windows.values():
                    state['queue'].append(pointer);insort(state['sorted'],duration[pointer])
                    state['late']+=late[pointer];state['duration']+=duration[pointer]
                pointer+=1
            values=[count,late_total,duration_total/count if count else np.nan]
            for days,state in windows.items():
                while state['queue'] and times[state['queue'][0]]<instant-days*DAY:
                    old=state['queue'].popleft();state['sorted'].pop(bisect_left(state['sorted'],duration[old]))
                    state['late']-=late[old];state['duration']-=duration[old]
                n=len(state['queue'])
                values += [n,state['late'],state['duration']/n if n else np.nan,
                           quantile(state['sorted'],.5),quantile(state['sorted'],.9)]
            output[int(position)]=values
    return pd.DataFrame(output,index=queries.index,columns=[f'h_{prefix}_{c}' for c in columns])

@dataclass
class HistoryStore:
    events: pd.DataFrame

    @classmethod
    def from_orders(cls,orders):
        ids=identities(orders)
        events=ids[['global_key','seller_id','route_state','route_prefix3','destination_prefix3']].copy()
        events['order_id']=orders.order_id.to_numpy()
        events['delivered_at']=pd.to_datetime(orders.delivered_at).to_numpy()
        events['dispatched_at']=pd.to_datetime(orders.dispatched_at).to_numpy()
        events['is_late']=orders.is_late.to_numpy()
        events['duration']=orders.event_duration.to_numpy()-1
        assert events.order_id.is_unique and events.delivered_at.ge(events.dispatched_at).all()
        return cls(events.reset_index(drop=True))

    def query(self,rows,cutoff=None):
        """cutoff congela o estado; None permite atualização causal a cada despacho."""
        ids=identities(rows).reset_index(drop=True)
        q=ids.copy();q['query_time']=pd.to_datetime(rows.dispatched_at).to_numpy()
        if cutoff is not None:
            q['query_time']=q.query_time.where(q.query_time<pd.Timestamp(cutoff),pd.Timestamp(cutoff))
        q['_position']=np.arange(len(q))
        blocks=[group_statistics(q,self.events,key,prefix) for key,prefix in GROUPS]
        result=pd.concat(blocks,axis=1)
        # A priori vem do histórico GLOBAL anterior à consulta, não da taxa do teste.
        for suffix in ['', '30','90']:
            global_rate=(result['h_global_late_sum'+suffix]+1)/(result['h_global_count'+suffix]+2)
            for _,prefix in GROUPS:
                n=result[f'h_{prefix}_count{suffix}'];late=result[f'h_{prefix}_late_sum{suffix}']
                result[f'h_{prefix}_late_rate{suffix}']=(late+20*global_rate)/(n+20)
                result=result.drop(columns=f'h_{prefix}_late_sum{suffix}')
        remaining=(pd.to_datetime(rows.estimated_delivery_at).dt.normalize()-pd.to_datetime(rows.dispatched_at).dt.normalize()).dt.days.to_numpy()
        for _,prefix in GROUPS:
            for days in [30,90]:
                for percentile in ['p50','p90']:
                    result[f'h_{prefix}_slack_{percentile}_{days}']=remaining-result[f'h_{prefix}_{percentile}_{days}']
        # Identificadores são categorias; nunca tratamos CEP como distância numérica.
        for c in ['origin_prefix3','destination_prefix3','route_prefix3']:
            result[c]=ids[c].to_numpy()
        result['history_missing_seller']=ids.seller_id.eq('UNKNOWN').astype(float)
        result['history_missing_zip']=ids.destination_prefix3.eq('UNKNOWN').astype(float)
        result.index=rows.index
        assert not result.columns.duplicated().any()
        return result
