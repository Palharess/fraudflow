"""Contrato da API: o que entra e o que sai."""
from datetime import date, datetime, timezone
from typing import Literal, Optional

from pydantic import BaseModel, Field, model_validator

# As 14 categorias que o modelo conhece. Uma categoria nova não daria erro no
# modelo, só seria tratada como ausente; aqui ela é recusada com 422.
Categoria = Literal[
    "entertainment", "food_dining", "gas_transport", "grocery_net",
    "grocery_pos", "health_fitness", "home", "kids_pets", "misc_net",
    "misc_pos", "personal_care", "shopping_net", "shopping_pos", "travel",
]


class Transacao(BaseModel):
    """Os nove campos do modelo, com as mesmas regras de validade da Silver."""

    transaction_id: Optional[str] = Field(None, description="Só para rastreabilidade; não entra no modelo.")
    transaction_ts: datetime = Field(description="Horário da transação. Sem fuso, é lido como UTC.")
    customer_dob: date
    customer_lat: float = Field(ge=-90, le=90)
    customer_long: float = Field(ge=-180, le=180)
    merchant_lat: float = Field(ge=-90, le=90)
    merchant_long: float = Field(ge=-180, le=180)
    amount: float = Field(gt=0)
    category: Categoria
    city_pop: int = Field(gt=0)

    @model_validator(mode="after")
    def nascimento_antes_da_compra(self):
        ts = self.transaction_ts
        dia = (ts.astimezone(timezone.utc) if ts.tzinfo else ts).date()
        if self.customer_dob >= dia:
            raise ValueError("customer_dob precisa ser anterior à data da transação")
        return self


class Pontuacao(BaseModel):
    transaction_id: Optional[str]
    fraud_score: float = Field(description="Score do modelo entre 0 e 1. Não é probabilidade calibrada.")
    modelo: str
    backend: str
    latencia_ms: float
