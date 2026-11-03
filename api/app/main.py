"""API de pontuação de fraude do FraudFlow."""
import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request

from .modelo import CAMPOS, ModeloLocal
from .schemas import Pontuacao, Transacao


@asynccontextmanager
async def lifespan(app):
    # O modelo é carregado uma vez, antes de o servidor aceitar conexões. No
    # Cloud Run, a instância só recebe tráfego depois disso.
    app.state.modelo = ModeloLocal(os.environ.get("MODELO_DIR", "/app/modelo"))
    yield


app = FastAPI(title="FraudFlow API", version="2.0", lifespan=lifespan)


@app.get("/health")
def health(request: Request):
    modelo = request.app.state.modelo
    return {"status": "ok", "backend": modelo.backend, "modelo": modelo.versao}


@app.post("/v1/score", response_model=Pontuacao)
def score(transacao: Transacao, request: Request):
    modelo = request.app.state.modelo
    inicio = time.perf_counter()
    fraud_score = modelo.pontuar([transacao.model_dump(include=set(CAMPOS))])[0]
    return Pontuacao(
        transaction_id=transacao.transaction_id,
        fraud_score=round(fraud_score, 6),
        modelo=modelo.versao,
        backend=modelo.backend,
        latencia_ms=round((time.perf_counter() - inicio) * 1000, 2),
    )
