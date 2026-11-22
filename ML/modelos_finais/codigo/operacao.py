"""Leitura dos arquivos finais, validação de entradas e avaliação dos classificadores."""
from pathlib import Path
import hashlib,json
import joblib,numpy as np,pandas as pd
from context_risk.contract import ContextShipment

COLUNAS_ENTRADA=['purchase_at','dispatched_at','estimated_delivery_at','seller_state','customer_state',
    'distance_km','total_weight_g','total_volume_cm3','items_count','sellers_count','price','freight_value',
    'seller_id','origin_prefix5','destination_prefix5']

def localizar_pasta(nome_modelo):
    """Aceita execução a partir da pasta do notebook ou da raiz do repositório."""
    for origem in [Path.cwd(),*Path.cwd().parents]:
        for pasta in [origem,origem/'ML/modelos_finais']:
            if (pasta/'artefatos'/f'{nome_modelo}.joblib').is_file():
                return pasta.resolve()
    raise FileNotFoundError('Abra o notebook na pasta ML/modelos_finais, mantendo os arquivos de apoio.')

def carregar_modelo(pasta,nome):
    """Confere a integridade antes de carregar os pesos selecionados."""
    pasta=Path(pasta)
    hashes=json.loads((pasta/'artefatos/integridade.json').read_text(encoding='utf-8'))
    for extensao in ['joblib','json']:
        relativo=f'artefatos/{nome}.{extensao}'
        assert hashlib.sha256((pasta/relativo).read_bytes()).hexdigest()==hashes[relativo],relativo
    return joblib.load(pasta/'artefatos'/f'{nome}.joblib')

def conferir_arquivo(pasta,relativo):
    pasta=Path(pasta)
    hashes=json.loads((pasta/'artefatos/integridade.json').read_text(encoding='utf-8'))
    assert hashlib.sha256((pasta/relativo).read_bytes()).hexdigest()==hashes[relativo],relativo

def carregar_avaliacao(pasta):
    """Preserva zeros nos prefixos CEP e a precisão das medidas numéricas."""
    conferir_arquivo(pasta,'dados/pedidos_avaliacao.csv.gz')
    frame=pd.read_csv(Path(pasta)/'dados/pedidos_avaliacao.csv.gz',
        dtype={'order_id':'string','seller_id':'string','origin_prefix5':'string','destination_prefix5':'string'},
        parse_dates=['purchase_at','dispatched_at','estimated_delivery_at'],float_precision='round_trip')
    assert len(frame)==19258 and frame.order_id.is_unique
    assert int(frame.atraso_real.sum())==704
    # Quantidades são inteiras no contrato, mesmo quando o CSV registra 1.0.
    for coluna in ['items_count','sellers_count']:
        valores=pd.to_numeric(frame[coluna],errors='raise')
        assert valores.notna().all() and valores.ge(1).all() and valores.eq(valores.round()).all()
        frame[coluna]=valores.astype('int64')
    return frame

def prever_pedido(modelo,pedido):
    """Recebe somente dados disponíveis no despacho; o desfecho não é aceito."""
    valores={k:(v.item() if isinstance(v,np.generic) else v) for k,v in pedido.items()}
    validado=ContextShipment.model_validate(valores)
    if any(getattr(validado,c) is None for c in ['seller_id','origin_prefix5','destination_prefix5']):
        raise ValueError('Informe o identificador real do vendedor e os prefixos CEP de origem e destino.')
    entrada=pd.DataFrame([validado.model_dump()])
    score=float(modelo.predict_proba(entrada)[0,1])
    return {'score':score,'limiar':float(modelo.threshold),
            'risco_sinalizado':bool(score>=modelo.threshold)}
