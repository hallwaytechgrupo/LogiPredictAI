"""Validação do pedido e das identidades utilizadas no histórico contextual."""
from pydantic import Field
from logipredict_final.contract import Shipment

class ContextShipment(Shipment):
    seller_id: str|None=Field(default=None,min_length=1,max_length=128)
    origin_prefix5: str|None=Field(default=None,pattern=r'^\d{5}$')
    destination_prefix5: str|None=Field(default=None,pattern=r'^\d{5}$')
