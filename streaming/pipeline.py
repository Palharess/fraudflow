"""Pipeline de streaming do FraudFlow: Pub/Sub → limpeza → BigQuery.

    Pub/Sub (transactions)
        → LimparEventos: tipagem, nomes canônicos, regras da Silver
            → válidos  → silver.transactions_stream
            → inválidos → silver.transactions_stream_errors (com o motivo)

Uma falha de gravação no BigQuery também vai para a tabela de erros, em vez de
travar o pipeline. As regras de limpeza ficam em limpeza.py.

Execução: streaming/run.sh (local com DirectRunner ou no Dataflow).
"""
import argparse
import logging
from datetime import datetime, timezone

import apache_beam as beam
from apache_beam.io.gcp.bigquery import BigQueryDisposition, WriteToBigQuery
from apache_beam.io.gcp.bigquery_tools import RetryStrategy
from apache_beam.metrics import Metrics
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

import limpeza

ERROS = "erros"


class _Limpar(beam.DoFn):
    def __init__(self):
        self.validos = Metrics.counter("limpeza", "eventos_validos")
        self.invalidos = Metrics.counter("limpeza", "eventos_invalidos")

    def process(self, mensagem):
        agora = datetime.now(timezone.utc)
        try:
            linha = limpeza.limpar(mensagem.data)
        except limpeza.EventoInvalido as erro:
            self.invalidos.inc()
            yield beam.pvalue.TaggedOutput(ERROS, limpeza.erro_para_bigquery(
                str(erro), mensagem.data, agora, mensagem.message_id,
                (mensagem.attributes or {}).get("transaction_id")))
            return
        self.validos.inc()
        yield limpeza.para_bigquery(linha, agora, mensagem.message_id)


class LimparEventos(beam.PTransform):
    """Separa as mensagens do Pub/Sub em linhas válidas e erros."""

    def expand(self, mensagens):
        return mensagens | beam.ParDo(_Limpar()).with_outputs(ERROS, main="validos")


def _falha_de_gravacao(falha):
    """Linha recusada pelo BigQuery: (tabela, linha, erros)."""
    _, linha, erros = falha
    motivo = erros[0].get("reason", "desconhecido") if erros else "desconhecido"
    return limpeza.erro_para_bigquery(
        f"falha_bigquery:{motivo}", repr(linha), datetime.now(timezone.utc),
        linha.get("pubsub_message_id"), linha.get("transaction_id"))


def _gravar(tabela):
    return WriteToBigQuery(
        tabela,
        method=WriteToBigQuery.Method.STREAMING_INSERTS,
        create_disposition=BigQueryDisposition.CREATE_NEVER,   # tabelas criadas pelo sql/stream/
        write_disposition=BigQueryDisposition.WRITE_APPEND,
        insert_retry_strategy=RetryStrategy.RETRY_ON_TRANSIENT_ERROR,
    )


def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--subscription", required=True,
                        help="projects/PROJETO/subscriptions/ASSINATURA")
    parser.add_argument("--tabela", required=True, help="PROJETO:silver.transactions_stream")
    parser.add_argument("--tabela_erros", required=True, help="PROJETO:silver.transactions_stream_errors")
    args, beam_args = parser.parse_known_args(argv)

    opcoes = PipelineOptions(beam_args, streaming=True, save_main_session=True)
    no_dataflow = opcoes.view_as(StandardOptions).runner == "DataflowRunner"

    with beam.Pipeline(options=opcoes) as p:
        mensagens = p | "Ler do Pub/Sub" >> beam.io.ReadFromPubSub(
            subscription=args.subscription,
            with_attributes=True,
            # O Pub/Sub entrega cada mensagem pelo menos uma vez. No Dataflow,
            # o atributo transaction_id descarta reenvios da mesma transação.
            # O DirectRunner não implementa essa opção.
            id_label="transaction_id" if no_dataflow else None,
        )
        limpas = mensagens | "Limpar eventos" >> LimparEventos()

        gravacao = limpas.validos | "Gravar válidos" >> _gravar(args.tabela)
        recusadas = gravacao.failed_rows_with_errors | "Falhas de gravação" >> beam.Map(_falha_de_gravacao)

        ((limpas[ERROS], recusadas)
         | "Juntar erros" >> beam.Flatten()
         | "Gravar erros" >> _gravar(args.tabela_erros))


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    run()
