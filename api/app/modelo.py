"""Modelo exportado do BigQuery ML, carregado dentro do container da API.

A exportação traz duas peças: o TRANSFORM como TensorFlow SavedModel
(transform/) e o XGBoost (model.bst, com os vocabulários em assets/). O
Predictor da biblioteca bigquery-ml-utils, mantida pelo Google, encadeia as
duas: recebe os nove campos crus e devolve a probabilidade de cada classe.
Nenhuma feature é calculada em Python.
"""
import json
import threading
from datetime import timezone
from pathlib import Path

# Os nove campos de entrada do modelo, os mesmos da gold.ml_input.
CAMPOS = (
    "transaction_ts", "customer_dob",
    "customer_lat", "customer_long", "merchant_lat", "merchant_long",
    "amount", "category", "city_pop",
)

# Como o TIMESTAMP chega ao TRANSFORM. Confirmado pelo teste de paridade
# (scripts/paridade.py) contra o ML.PREDICT.
FORMATO_TS = "%Y-%m-%d %H:%M:%S"


class ModeloLocal:
    backend = "modelo-local"

    def __init__(self, diretorio, formato_ts=FORMATO_TS):
        # Importado aqui, e não no topo: o serviço de contingência, que consulta
        # o ML.PREDICT, não instala nem carrega o TensorFlow.
        from bigquery_ml_utils.inference.transform_predictor.predictor import Predictor

        diretorio = Path(diretorio)
        self._predictor = Predictor.from_path(str(diretorio))
        metadados = json.loads((diretorio / "assets" / "model_metadata.json").read_text())
        self._rotulo = metadados["label_col"]
        arquivo_versao = diretorio / "VERSAO"
        self.versao = arquivo_versao.read_text().strip() if arquivo_versao.is_file() else "sem VERSAO"
        self.formato_ts = formato_ts
        # Uma predição por vez: evita depender da segurança de threads do
        # TensorFlow e do XGBoost quando o Cloud Run atende requisições em paralelo.
        self._trava = threading.Lock()

    def entrada(self, transacao):
        """Converte os campos canônicos para os tipos que o TRANSFORM recebe."""
        ts = transacao["transaction_ts"]
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        return {
            "transaction_ts": ts.astimezone(timezone.utc).strftime(self.formato_ts),
            "customer_dob":   transacao["customer_dob"].isoformat(),
            "customer_lat":   float(transacao["customer_lat"]),
            "customer_long":  float(transacao["customer_long"]),
            "merchant_lat":   float(transacao["merchant_lat"]),
            "merchant_long":  float(transacao["merchant_long"]),
            "amount":         float(transacao["amount"]),
            "category":       str(transacao["category"]),
            "city_pop":       int(transacao["city_pop"]),
        }

    def pontuar(self, transacoes):
        """fraud_score de cada transação: a probabilidade da classe '1'."""
        instancias = [self.entrada(t) for t in transacoes]
        with self._trava:
            saidas = self._predictor.predict(instancias)
        return [self._score(saida) for saida in saidas]

    def _score(self, saida):
        valores = [str(v) for v in saida[f"{self._rotulo}_values"]]
        return float(saida[f"{self._rotulo}_probs"][valores.index("1")])
