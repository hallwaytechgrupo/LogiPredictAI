"""CSV real -> uma linha por pedido; nenhuma observação sintética."""
import os,json,hashlib,tempfile,subprocess
from pathlib import Path
import numpy as np
import pandas as pd
from .features import feature_frame
DATA_COMMIT='8fbdf36cc75da4befa2c81a726bbbcf646205ed0'
BR_LAT_BOUNDS=(-35,6)
BR_LON_BOUNDS=(-75,-28)
# 1. Localizando os seis CSVs, sem alterar a branch ou gravar credenciais
REQUIRED_TABLES = ['orders', 'order_items', 'customers', 'products', 'sellers', 'geolocation']
REQUIRED_FILES = [f'olist_{name}_dataset.csv' for name in REQUIRED_TABLES]

def locate_dataset():
    configured = os.environ.get('OLIST_DATASET_PATH')
    if configured:
        directory = Path(configured).expanduser()
        if not all((directory / name).is_file() for name in REQUIRED_FILES):
            raise FileNotFoundError('OLIST_DATASET_PATH deve conter os seis CSVs Olist completos.')
        return directory, {'mode': 'local_csv'}
    roots = list(dict.fromkeys([Path.cwd(), *Path.cwd().parents,
                               *Path(__file__).resolve().parents]))
    roots += [p / 'LogiPredictAI' for p in roots.copy()]
    for root in roots:
        for directory in [root / 'back/data/raw', root / 'data/raw', root]:
            if all((directory / name).is_file() for name in REQUIRED_FILES):
                return directory, {'mode': 'local_csv'}
    # Os arquivos versionados também podem ser lidos a partir do commit registrado.
    # A extração vai para o diretório temporário; o checkout permanece intacto.
    for root in roots:
        if not (root / '.git').exists():
            continue
        try:
            commit = subprocess.check_output(['git', 'rev-parse', DATA_COMMIT], cwd=root,
                                             stderr=subprocess.DEVNULL, text=True).strip()
            for name in REQUIRED_FILES:
                subprocess.run(['git', 'cat-file', '-e', f'{commit}:back/data/raw/{name}'],
                    cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            directory = Path(tempfile.gettempdir()) / f'logipredict-olist-{commit[:12]}'
            directory.mkdir(parents=True, exist_ok=True)
            for name in REQUIRED_FILES:
                blob = subprocess.check_output(['git', 'show', f'{commit}:back/data/raw/{name}'], cwd=root)
                target = directory / name
                if not target.exists() or hashlib.sha256(target.read_bytes()).digest() != hashlib.sha256(blob).digest():
                    target.write_bytes(blob)
            return directory, {'mode': 'local_git_objects', 'commit': commit}
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    raise FileNotFoundError('Defina OLIST_DATASET_PATH com os seis CSVs Olist completos.')


# 2. Uma linha por pedido, com agregação de todos os itens e vendedores
REGIONS = {
    **dict.fromkeys('AC AP AM PA RO RR TO'.split(), 'Norte'),
    **dict.fromkeys('AL BA CE MA PB PE PI RN SE'.split(), 'Nordeste'),
    **dict.fromkeys('DF GO MT MS'.split(), 'Centro-Oeste'),
    **dict.fromkeys('ES MG RJ SP'.split(), 'Sudeste'),
    **dict.fromkeys('PR RS SC'.split(), 'Sul'),
}

def normalize_prefix(values):
    return values.astype('string').str.strip().str.replace(r'\.0$', '', regex=True).str.zfill(5).where(
        lambda x: x.str.fullmatch(r'\d{5}', na=False))

def haversine(lat1, lon1, lat2, lon2):
    a1, o1, a2, o2 = map(np.radians, [lat1, lon1, lat2, lon2])
    a = np.sin((a2-a1)/2)**2 + np.cos(a1)*np.cos(a2)*np.sin((o2-o1)/2)**2
    return 6371.0088 * 2 * np.arcsin(np.sqrt(np.clip(a, 0, 1)))

def prepare_orders(tables):
    t = {name: data.drop_duplicates().copy() for name, data in tables.items()}
    for name, keys in [('orders',['order_id']), ('order_items',['order_id','order_item_id']),
                       ('customers',['customer_id']), ('sellers',['seller_id']), ('products',['product_id'])]:
        if t[name][keys].isna().any().any() or t[name].duplicated(keys).any():
            raise ValueError(f'Chaves nulas ou conflitantes: {name}, {keys}')
    orders, items, products = t['orders'], t['order_items'], t['products']
    customers, sellers, geo = t['customers'], t['sellers'], t['geolocation']
    for table, column in [(customers,'customer_zip_code_prefix'),(sellers,'seller_zip_code_prefix'),
                           (geo,'geolocation_zip_code_prefix')]:
        table[column] = normalize_prefix(table[column])
    for column, limit in [('geolocation_lat',90),('geolocation_lng',180)]:
        geo[column] = pd.to_numeric(geo[column], errors='coerce')
        geo.loc[~geo[column].between(-limit,limit), column] = np.nan
    invalid_geo = (~geo.geolocation_lat.between(*BR_LAT_BOUNDS)
                   | ~geo.geolocation_lng.between(*BR_LON_BOUNDS))
    geo_rows_filtered = int(invalid_geo.sum())
    geo.loc[invalid_geo,['geolocation_lat','geolocation_lng']] = np.nan
    geo = geo.groupby('geolocation_zip_code_prefix')[['geolocation_lat','geolocation_lng']].median()
    customers = customers.merge(geo, left_on='customer_zip_code_prefix', right_index=True, how='left', validate='many_to_one')
    customers = customers.rename(columns={'customer_zip_code_prefix':'destination_prefix5','customer_state':'destination_state',
        'customer_city':'destination_city','geolocation_lat':'destination_lat','geolocation_lng':'destination_lon'})
    sellers = sellers.merge(geo, left_on='seller_zip_code_prefix', right_index=True, how='left', validate='many_to_one')
    sellers = sellers.rename(columns={'seller_zip_code_prefix':'origin_prefix5','seller_state':'origin_state',
        'seller_city':'origin_city','geolocation_lat':'origin_lat','geolocation_lng':'origin_lon'})
    physical = ['product_weight_g','product_length_cm','product_height_cm','product_width_cm']
    listing = ['product_name_lenght','product_description_lenght','product_photos_qty']
    for column in physical + listing:
        products[column] = pd.to_numeric(products[column], errors='coerce')
        invalid = ~np.isfinite(products[column]) | (products[column] < 0)
        if column in physical:
            invalid |= products[column].eq(0)
        products.loc[invalid,column] = np.nan
    products['product_volume_cm3'] = products.product_length_cm * products.product_height_cm * products.product_width_cm
    products['product_category_name'] = products.product_category_name.fillna('DESCONHECIDA')
    for column in ['price','freight_value']:
        items[column] = pd.to_numeric(items[column], errors='coerce')
        items.loc[(items[column] < 0) | ~np.isfinite(items[column]), column] = np.nan
    items['shipping_limit_date'] = pd.to_datetime(items.shipping_limit_date, errors='coerce')
    details = items.sort_values(['order_id','order_item_id']).merge(products,on='product_id',how='left',validate='many_to_one')
    details = details.merge(sellers,on='seller_id',how='left',validate='many_to_one')
    details = details.merge(orders[['order_id','customer_id']],on='order_id',how='left',validate='many_to_one')
    details = details.merge(customers[['customer_id','destination_lat','destination_lon']],on='customer_id',how='left',validate='many_to_one')
    details['distance_km'] = haversine(details.origin_lat, details.origin_lon, details.destination_lat, details.destination_lon)
    grouped = details.groupby('order_id', sort=False)
    aggregate = grouped.size().rename('items_count').to_frame()
    for source, target in [('price','price'),('freight_value','freight_value'),('product_weight_g','total_weight_g'),
                            ('product_volume_cm3','total_volume_cm3')]:
        aggregate[target] = grouped[source].sum(min_count=1).where(grouped[source].count().eq(aggregate.items_count))
    for source, target in [('product_length_cm','max_product_length_cm'),('product_height_cm','max_product_height_cm'),
                            ('product_width_cm','max_product_width_cm'),('distance_km','distance_km')]:
        aggregate[target] = grouped[source].max().where(grouped[source].count().eq(aggregate.items_count))
    aggregate['distance_mean_km'] = grouped.distance_km.mean()
    aggregate['sellers_count'] = grouped.seller_id.nunique()
    aggregate['categories_count'] = grouped.product_category_name.nunique()
    aggregate['origin_states_count'] = grouped.origin_state.nunique()
    aggregate['physical_missing_share'] = grouped.product_weight_g.apply(lambda x: x.isna().mean())
    aggregate['shipping_limit_min_at'] = grouped.shipping_limit_date.min()
    aggregate['shipping_limit_max_at'] = grouped.shipping_limit_date.max()
    for source in listing:
        aggregate['mean_'+source] = grouped[source].mean()
    first = details.drop_duplicates('order_id',keep='first').set_index('order_id')
    for column in ['seller_id','origin_prefix5','origin_state','origin_city','origin_lat','origin_lon']:
        aggregate[column] = first[column]
    category = (details.groupby(['order_id','product_category_name']).size().rename('n').reset_index()
        .sort_values(['order_id','n','product_category_name'],ascending=[True,False,True])
        .drop_duplicates('order_id').set_index('order_id').product_category_name)
    aggregate['product_category'] = category
    frame = orders.merge(aggregate,on='order_id',how='left',validate='one_to_one')
    frame = frame.merge(customers[['customer_id','destination_prefix5','destination_city','destination_state',
                                   'destination_lat','destination_lon']],on='customer_id',how='left',validate='many_to_one')
    frame = frame.rename(columns={'order_purchase_timestamp':'purchase_at','order_approved_at':'approved_at',
        'order_delivered_carrier_date':'dispatch_at','order_delivered_customer_date':'outcome_at',
        'order_estimated_delivery_date':'promised_at'})
    for column in ['purchase_at','approved_at','dispatch_at','outcome_at','promised_at']:
        frame[column] = pd.to_datetime(frame[column],errors='coerce')
    valid = (frame.order_status.eq('delivered') & frame[['purchase_at','dispatch_at','outcome_at','promised_at']].notna().all(axis=1)
        & frame.dispatch_at.ge(frame.purchase_at) & frame.outcome_at.ge(frame.dispatch_at)
        & frame.promised_at.dt.normalize().ge(frame.purchase_at.dt.normalize())
        & frame[['price','freight_value','items_count']].notna().all(axis=1)
        & frame.origin_state.isin(REGIONS) & frame.destination_state.isin(REGIONS))
    frame = frame.loc[valid].sort_values(['dispatch_at','order_id']).reset_index(drop=True)
    frame['is_late'] = frame.outcome_at.dt.normalize().gt(frame.promised_at.dt.normalize()).astype('int8')
    frame['transit_days'] = (frame.outcome_at-frame.dispatch_at).dt.total_seconds()/86400
    frame['dispatch_lead_days'] = (frame.dispatch_at-frame.purchase_at).dt.total_seconds()/86400
    frame['remaining_days'] = (frame.promised_at.dt.normalize()-frame.dispatch_at.dt.normalize()).dt.days
    frame['already_overdue'] = frame.remaining_days.lt(0)
    for side in ['origin','destination']:
        frame[side+'_region'] = frame[side+'_state'].map(REGIONS)
        frame[side+'_prefix3'] = frame[side+'_prefix5'].str[:3]
        frame[side+'_city'] = frame[side+'_city'].astype('string').str.strip().str.casefold()
    frame['route_state'] = frame.origin_state+'>'+frame.destination_state
    frame['route_region'] = frame.origin_region+'>'+frame.destination_region
    frame['route_prefix3'] = frame.origin_prefix3.fillna('???')+'>'+frame.destination_prefix3.fillna('???')
    frame['estimated_delivery_days'] = (frame.promised_at-frame.purchase_at).dt.total_seconds()/86400
    frame['required_speed_km_day'] = frame.distance_km/(frame.estimated_delivery_days+1)
    frame['remaining_speed_km_day'] = frame.distance_km/(frame.remaining_days.clip(lower=0)+1)
    frame['product_density'] = frame.total_weight_g/(frame.total_volume_cm3+1e-5)
    frame['dispatch_fraction'] = frame.dispatch_lead_days/(frame.estimated_delivery_days+1)
    frame['freight_ratio'] = frame.freight_value/(frame.price+1)
    frame['freight_per_item'] = frame.freight_value/frame.items_count
    frame['price_per_item'] = frame.price/frame.items_count
    frame['weight_per_item_g'] = frame.total_weight_g/frame.items_count
    frame['is_interstate'] = frame.origin_state.ne(frame.destination_state).astype('int8')
    frame['is_interregion'] = frame.origin_region.ne(frame.destination_region).astype('int8')
    frame['approval_lead_days'] = ((frame.approved_at-frame.purchase_at).dt.total_seconds()/86400).where(
        frame.approved_at.between(frame.purchase_at,frame.dispatch_at))
    frame['approval_missing_or_not_yet_known'] = frame.approval_lead_days.isna().astype('int8')
    for label in ['min','max']:
        frame['shipping_limit_'+label+'_lag_days'] = (frame.dispatch_at-frame['shipping_limit_'+label+'_at']).dt.total_seconds()/86400
    for label, column in [('purchase','purchase_at'),('dispatch','dispatch_at'),('promised','promised_at')]:
        frame[label+'_weekday'] = frame[column].dt.weekday
        frame[label+'_month'] = frame[column].dt.month
        frame[label+'_day'] = frame[column].dt.day
    frame['purchase_hour'] = frame.purchase_at.dt.hour
    frame['dispatch_hour'] = frame.dispatch_at.dt.hour
    frame['purchase_month_sin'] = np.sin(2*np.pi*frame.purchase_month/12)
    frame['purchase_month_cos'] = np.cos(2*np.pi*frame.purchase_month/12)
    frame['purchase_weekday_sin'] = np.sin(2*np.pi*frame.purchase_weekday/7)
    frame['purchase_weekday_cos'] = np.cos(2*np.pi*frame.purchase_weekday/7)
    frame['is_peak_month'] = frame.purchase_month.isin([11,12]).astype('int8')
    bridge = details[['order_id','seller_id','origin_state','origin_prefix5']].drop_duplicates(['order_id','seller_id'])
    bridge = bridge.loc[bridge.order_id.isin(frame.order_id)].copy()
    bridge['seller_destination'] = bridge.seller_id.astype(str)+'>'+bridge.order_id.map(frame.set_index('order_id').destination_state)
    quality = {'raw_orders':len(orders),'eligible_orders':len(frame),'late_orders':int(frame.is_late.sum()),
        'late_rate':float(frame.is_late.mean()),'sellers':sellers.seller_id.nunique(),
        'orders_with_missing_measure':int(frame[['distance_km','total_weight_g','total_volume_cm3']].isna().any(axis=1).sum()),
        'multiple_seller_orders':int(frame.sellers_count.gt(1).sum()),
        'geo_rows_filtered_after_dedup':geo_rows_filtered}
    assert frame.order_id.is_unique and frame.loc[frame.already_overdue,'is_late'].eq(1).all()
    for side in ['origin','destination']:
        present = frame[side+'_lat'].notna()
        assert frame.loc[present,side+'_lat'].between(*BR_LAT_BOUNDS).all()
        assert frame.loc[present,side+'_lon'].between(*BR_LON_BOUNDS).all()
    return frame, bridge, quality


def load_orders(raw_dir=None):
    directory=Path(raw_dir) if raw_dir else locate_dataset()[0]
    tables={};manifest=[]
    for name in REQUIRED_TABLES:
        path=directory/f'olist_{name}_dataset.csv'
        tables[name]=pd.read_csv(path,dtype={c:'string' for c in ['customer_zip_code_prefix','seller_zip_code_prefix','geolocation_zip_code_prefix']})
        manifest.append({'table':name,'rows':len(tables[name]),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    base,_,quality=prepare_orders(tables)
    base=base.rename(columns={'dispatch_at':'dispatched_at','outcome_at':'delivered_at','promised_at':'estimated_delivery_at',
        'origin_state':'seller_state','destination_state':'customer_state'})
    base['deadline_ends']=base.estimated_delivery_at.dt.normalize()+pd.Timedelta(days=1)
    base['label_known_at']=base.delivered_at.where(base.delivered_at<base.deadline_ends,base.deadline_ends)
    base['event_duration']=(base.delivered_at.dt.normalize()-base.dispatched_at.dt.normalize()).dt.days+1.
    assert base.event_duration.gt(0).all() and base.order_id.is_unique
    assert base.loc[base.label_known_at<base.delivered_at,'is_late'].eq(1).all()
    return base.reset_index(drop=True),{'quality':quality,'manifest':manifest,'dataset_commit':DATA_COMMIT}

def shipment_row(row):
    """Exemplo real exportável para o Shipment da main, sem alvo nem data de entrega."""
    numeric=['distance_km','total_weight_g','total_volume_cm3','price','freight_value']
    out={c:(None if pd.isna(row[c]) else float(row[c])) for c in numeric}
    out.update({c:pd.Timestamp(row[c]).isoformat() for c in ['purchase_at','dispatched_at','estimated_delivery_at']})
    out.update({c:str(row[c]) for c in ['seller_state','customer_state']})
    out.update({c:int(row[c]) for c in ['items_count','sellers_count']})
    return out
