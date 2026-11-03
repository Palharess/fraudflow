"""Os dois backends de pontuação da API. Os dois recebem os mesmos nove campos
e devolvem o mesmo score.

ModeloLocal — o principal. A exportação do BigQuery ML traz o TRANSFORM como
TensorFlow SavedModel (transform/) e o XGBoost (model.bst, com os vocabulários
em assets/). Aqui as duas peças são encadeadas: os campos crus passam pelo
TRANSFORM, e as features que ele devolve vão para o preditor XGBoost da
biblioteca bigquery-ml-utils, mantida pelo Google. Nenhuma feature é calculada
em Python.

ModeloBigQuery — a contingência. Consulta o ML.PREDICT do próprio BigQuery:
mais lento, mas sem TensorFlow e sem artefato no container.
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

# O TRANSFORM recebe o TIMESTAMP como texto e só aceita o fuso no formato +00.
# Sem ele, as funções de data recusam a entrada. Confirmado pelo teste de
# paridade (scripts/paridade.py): mesmas features do ML.TRANSFORM e mesmo
# score do ML.PREDICT nas 50 transações da amostra.
FORMATO_TS = "%Y-%m-%d %H:%M:%S+00"


def _score_da_classe_1(probabilidades):
    """Probabilidade da classe '1' numa lista de {label, prob} do BigQuery."""
    return next(p["prob"] for p in probabilidades if str(p["label"]) == "1")


def _como_vocabulario(valor):
    """Converte uma feature do TRANSFORM para a forma gravada nos vocabulários.

    O vocabulário exportado guarda BOOL como 'true'/'false'. A biblioteca
    entregaria True/False ao XGBoost; fora do vocabulário, o valor viraria
    ausente, e is_night é a feature mais forte do modelo.
    """
    if isinstance(valor, bool):
        return "true" if valor else "false"
    if isinstance(valor, bytes):
        return valor.decode("utf-8")
    return valor


class ModeloLocal:
    backend = "modelo-local"

    def __init__(self, diretorio, formato_ts=FORMATO_TS):
        # Importados aqui, e não no topo: o serviço de contingência, que consulta
        # o ML.PREDICT, não instala nem carrega o TensorFlow.
        import tensorflow as tf
        # Importar este módulo registra as operações de data do BigQuery que o
        # TRANSFORM usa (DATE_DIFF, EXTRACT...).
        import bigquery_ml_utils.inference.transform_predictor.predictor  # noqa: F401
        from bigquery_ml_utils.inference.xgboost_predictor.predictor import Predictor

        diretorio = Path(diretorio)
        self._tf = tf
        self._transform = tf.saved_model.load(str(diretorio / "transform")).signatures["serving_default"]
        self._entradas = self._transform.structured_input_signature[1]
        self._xgboost = Predictor.from_path(str(diretorio))
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

    def features(self, transacoes):
        """Roda o TRANSFORM e devolve as features de cada transação."""
        instancias = [self.entrada(t) for t in transacoes]
        colunas = {
            nome: self._tf.constant([i[nome] for i in instancias], spec.dtype)
            for nome, spec in self._entradas.items()
        }
        saida = self._transform(**colunas)
        linhas = [{} for _ in instancias]
        for nome, tensor in saida.items():
            for linha, valor in zip(linhas, tensor.numpy().tolist()):
                linha[nome] = _como_vocabulario(valor)
        return linhas

    def pontuar(self, transacoes):
        """fraud_score de cada transação: a probabilidade da classe '1'."""
        with self._trava:
            saidas = self._xgboost.predict(self.features(transacoes))
        return [self._score(saida) for saida in saidas]

    def _score(self, saida):
        valores = [str(v) for v in saida[f"{self._rotulo}_values"]]
        return float(saida[f"{self._rotulo}_probs"][valores.index("1")])


class ModeloBigQuery:
    backend = "bigquery-ml-predict"

    def __init__(self, projeto, modelo="gold.fraud_boosted"):
        from google.cloud import bigquery

        self._bq = bigquery
        self._cliente = bigquery.Client(project=projeto, location="us-central1")
        referencia = f"{projeto}.{modelo}"
        treinado = self._cliente.get_model(referencia).modified
        self.versao = f"{modelo} · BigQuery ML · treinado em {treinado:%d/%m/%Y %H:%M} UTC"
        # As transações vão como parâmetro, nunca concatenadas no SQL. O índice
        # i preserva a ordem da resposta.
        self._sql = f"""
            SELECT i, predicted_is_fraud_probs AS probs
            FROM ML.PREDICT(MODEL `{referencia}`, (SELECT * FROM UNNEST(@linhas)))
            ORDER BY i
        """

    def _linha(self, i, t):
        bq = self._bq
        campos = [
            bq.ScalarQueryParameter("i", "INT64", i),
            bq.ScalarQueryParameter("transaction_ts", "TIMESTAMP", t["transaction_ts"]),
            bq.ScalarQueryParameter("customer_dob", "DATE", t["customer_dob"]),
        ]
        campos += [bq.ScalarQueryParameter(c, "FLOAT64", float(t[c]))
                   for c in ("customer_lat", "customer_long", "merchant_lat", "merchant_long", "amount")]
        campos += [
            bq.ScalarQueryParameter("category", "STRING", str(t["category"])),
            bq.ScalarQueryParameter("city_pop", "INT64", int(t["city_pop"])),
        ]
        return bq.StructQueryParameter(None, *campos)

    def pontuar(self, transacoes):
        parametro = self._bq.ArrayQueryParameter(
            "linhas", "STRUCT", [self._linha(i, t) for i, t in enumerate(transacoes)])
        linhas = self._cliente.query_and_wait(
            self._sql, job_config=self._bq.QueryJobConfig(query_parameters=[parametro]))
        return [float(_score_da_classe_1(linha["probs"])) for linha in linhas]
