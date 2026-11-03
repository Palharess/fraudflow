"""Gerador de eventos do FraudFlow: reproduz o fraudTest.csv no Pub/Sub.

As transações são publicadas na ordem do arquivo, que é cronológica, e
continuam a linha do tempo de onde o histórico (fraudTrain) para. Cada linha
vira um evento JSON com os campos de origem, nos nomes e no formato de texto do
CSV: a tipagem e a limpeza são trabalho do pipeline. Ficam de fora o rótulo
is_fraud, os dados pessoais (nome, endereço, gênero, profissão) e o unix_time.

O horário da transação é o original. O horário real da publicação vai no campo
published_at.

Com --invalidos N, o gerador intercala N eventos inválidos sintéticos, com ids
próprios, para demonstrar a tabela de erros. As transações reais não são
alteradas.

Uso:
    python publisher.py --taxa 20 --limite 2000
    python publisher.py --taxa 20 --limite 2000 --invalidos 12
    python publisher.py --inicio 2000 --taxa 50          # continua de onde parou
    python publisher.py --simular --limite 3             # só imprime, não publica
"""
import argparse
import csv
import json
import sys
import time
import uuid
from datetime import datetime, timezone
from itertools import islice

ORIGEM = "gs://fraudflow-pdm-gps-data/holdout/fraudTest.csv"

# Campos publicados, com os nomes do CSV de origem.
CAMPOS = (
    "trans_num", "trans_date_trans_time", "cc_num", "merchant", "category",
    "amt", "lat", "long", "state", "city_pop", "dob", "merch_lat", "merch_long",
)

# Eventos inválidos de teste: o motivo que o pipeline deve registrar e como o
# evento é estragado. O último não é nem JSON.
INVALIDOS = (
    ("valor_nao_positivo",                   lambda e: {**e, "amt": "-12.50"}),
    ("tipo_invalido:trans_date_trans_time",  lambda e: {**e, "trans_date_trans_time": "2020-13-45 25:61:00"}),
    ("fora_do_intervalo:customer_lat",       lambda e: {**e, "lat": "123.45"}),
    ("campo_ausente:amt",                    lambda e: {k: v for k, v in e.items() if k != "amt"}),
    ("nascimento_apos_transacao",            lambda e: {**e, "dob": "2030-01-01"}),
    ("json_invalido",                        None),
)


def linhas_csv(origem):
    """Lê o CSV linha a linha, sem baixar o arquivo inteiro."""
    if origem.startswith("gs://"):
        from google.cloud import storage

        bucket, _, nome = origem.removeprefix("gs://").partition("/")
        arquivo = storage.Client().bucket(bucket).blob(nome).open("r", encoding="utf-8", newline="")
    else:
        arquivo = open(origem, encoding="utf-8", newline="")
    with arquivo:
        yield from csv.DictReader(arquivo)


def agora():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def evento_valido(linha):
    return {**{c: linha[c] for c in CAMPOS}, "published_at": agora()}


def evento_invalido(base, numero):
    """O n-ésimo evento inválido, a partir de um evento real copiado."""
    motivo, estragar = INVALIDOS[numero % len(INVALIDOS)]
    transaction_id = f"teste-invalido-{uuid.uuid4().hex[:12]}"
    if estragar is None:
        dados = f'{{"trans_num": "{transaction_id}", "amt": '.encode()   # JSON cortado
    else:
        dados = json.dumps(estragar({**base, "trans_num": transaction_id, "published_at": agora()})).encode()
    return transaction_id, motivo, dados


class Destino:
    """Publica no Pub/Sub, ou só imprime com --simular."""

    def __init__(self, projeto, topico, simular):
        self.simular = simular
        self.pendentes = []
        if not simular:
            from google.cloud import pubsub_v1

            self.cliente = pubsub_v1.PublisherClient(
                batch_settings=pubsub_v1.types.BatchSettings(max_messages=100, max_latency=0.05))
            self.topico = self.cliente.topic_path(projeto, topico)

    def publicar(self, dados, **atributos):
        if self.simular:
            print(dados.decode(), atributos)
            return
        self.pendentes.append(self.cliente.publish(self.topico, dados, **atributos))
        if len(self.pendentes) >= 500:
            self.confirmar()

    def confirmar(self):
        """Espera o Pub/Sub confirmar o que foi enviado. Uma falha interrompe."""
        for futuro in self.pendentes:
            futuro.result(timeout=60)
        self.pendentes.clear()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--projeto", default="fraudflow-pdm-gps")
    parser.add_argument("--topico", default="transactions")
    parser.add_argument("--origem", default=ORIGEM, help="CSV no GCS (gs://...) ou local")
    parser.add_argument("--taxa", type=float, default=20, help="eventos por segundo")
    parser.add_argument("--limite", type=int, default=None, help="quantas transações publicar")
    parser.add_argument("--inicio", type=int, default=0, help="pula as N primeiras linhas")
    parser.add_argument("--invalidos", type=int, default=0, help="eventos inválidos de teste a intercalar")
    parser.add_argument("--intervalo-invalidos", type=int, default=25,
                        help="um inválido a cada N transações válidas")
    parser.add_argument("--simular", action="store_true", help="imprime em vez de publicar")
    args = parser.parse_args()

    destino = Destino(args.projeto, args.topico, args.simular)
    fim = args.inicio + args.limite if args.limite is not None else None
    validos = invalidos = fora_de_ordem = 0
    primeira = ultima = None
    inicio = time.monotonic()

    print(f"Publicando {args.origem} → {args.topico} a {args.taxa:g} eventos/s "
          f"(linhas {args.inicio} a {fim if fim is not None else 'fim'})", file=sys.stderr)
    try:
        for linha in islice(linhas_csv(args.origem), args.inicio, fim):
            evento = evento_valido(linha)
            if ultima is not None and evento["trans_date_trans_time"] < ultima:
                fora_de_ordem += 1
            primeira = primeira or evento["trans_date_trans_time"]
            ultima = evento["trans_date_trans_time"]

            # O atributo transaction_id permite ao Dataflow descartar reenvios.
            destino.publicar(json.dumps(evento).encode(),
                             transaction_id=evento["trans_num"], fonte="replay-fraudTest")
            validos += 1

            if invalidos < args.invalidos and validos % args.intervalo_invalidos == 0:
                transaction_id, motivo, dados = evento_invalido(evento, invalidos)
                destino.publicar(dados, transaction_id=transaction_id, fonte="teste-invalido",
                                 motivo_esperado=motivo)
                invalidos += 1

            # Ritmo constante: dorme o necessário para não passar da taxa.
            atraso = inicio + (validos + invalidos) / args.taxa - time.monotonic()
            if atraso > 0:
                time.sleep(atraso)
            if validos % 200 == 0:
                print(f"  {validos} transações · última de {ultima}", file=sys.stderr)
    except KeyboardInterrupt:
        print("\nInterrompido.", file=sys.stderr)
    finally:
        destino.confirmar()

    segundos = time.monotonic() - inicio
    print(f"\n{validos} transações e {invalidos} inválidos de teste em {segundos:.0f} s "
          f"({(validos + invalidos) / max(segundos, 1e-9):.1f}/s)", file=sys.stderr)
    print(f"Período reproduzido: {primeira} → {ultima}", file=sys.stderr)
    if fora_de_ordem:
        print(f"Atenção: {fora_de_ordem} transações fora de ordem cronológica", file=sys.stderr)
    print(f"Para continuar: --inicio {args.inicio + validos}", file=sys.stderr)


if __name__ == "__main__":
    main()
