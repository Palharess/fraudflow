"""Limpeza do evento de transação: as mesmas regras da camada Silver.

Python puro, sem o Beam: o pipeline usa estas funções, e os testes rodam sem
nenhuma dependência.

O evento chega como o gerador o publica: os campos do CSV de origem, com os
nomes originais e os valores em texto. Daqui sai uma linha da
silver.transactions_stream, com nomes canônicos e tipos do BigQuery. A única
regra da Silver que não se aplica é is_fraud IN (0, 1): o evento não traz
rótulo.
"""
import json
import math
import re
from datetime import datetime, timezone

# Campos que o evento precisa trazer, com os nomes do CSV de origem.
OBRIGATORIOS = (
    "trans_num", "trans_date_trans_time", "cc_num", "merchant", "category",
    "amt", "lat", "long", "state", "city_pop", "dob", "merch_lat", "merch_long",
)


class EventoInvalido(ValueError):
    """O motivo é um código curto, gravado na tabela de erros."""


def _numero(evento, campo, tipo=float):
    try:
        valor = tipo(evento[campo])
    except (TypeError, ValueError, OverflowError):
        raise EventoInvalido(f"tipo_invalido:{campo}") from None
    # "inf" e "nan" viram float sem erro, e infinito passaria em "valor > 0".
    if not math.isfinite(valor):
        raise EventoInvalido(f"tipo_invalido:{campo}")
    return valor


def _data_hora(texto, formato, campo):
    try:
        return datetime.strptime(texto, formato)
    except (TypeError, ValueError):
        raise EventoInvalido(f"tipo_invalido:{campo}") from None


def limpar(bruto):
    """Converte o evento cru (bytes ou texto JSON) numa linha canônica.

    Levanta EventoInvalido com o motivo quando o evento não passa nas regras.
    """
    try:
        evento = json.loads(bruto)
    except ValueError:
        raise EventoInvalido("json_invalido") from None
    if not isinstance(evento, dict):
        raise EventoInvalido("json_invalido")

    ausentes = [c for c in OBRIGATORIOS if evento.get(c) in (None, "")]
    if ausentes:
        raise EventoInvalido("campo_ausente:" + ",".join(ausentes))

    # O horário é o da transação, como na Silver: é dele que saem hour,
    # is_night e age no modelo. O horário de processamento fica à parte.
    transaction_ts = _data_hora(evento["trans_date_trans_time"], "%Y-%m-%d %H:%M:%S",
                                "trans_date_trans_time").replace(tzinfo=timezone.utc)
    customer_dob = _data_hora(evento["dob"], "%Y-%m-%d", "dob").date()

    linha = {
        "transaction_id": str(evento["trans_num"]),
        "card_id":        str(evento["cc_num"]),
        "transaction_ts": transaction_ts,
        "amount":         _numero(evento, "amt"),
        "category":       str(evento["category"]),
        # O prefixo fraud_ é artefato do gerador do dataset, inclusive em
        # transações legítimas. A Silver remove, aqui também.
        "merchant_name":  re.sub(r"^fraud_", "", str(evento["merchant"])),
        "customer_dob":   customer_dob,
        "customer_lat":   _numero(evento, "lat"),
        "customer_long":  _numero(evento, "long"),
        "customer_state": str(evento["state"]),
        "city_pop":       _numero(evento, "city_pop", int),
        "merchant_lat":   _numero(evento, "merch_lat"),
        "merchant_long":  _numero(evento, "merch_long"),
    }

    # Regras de validade da Silver (sql/silver/10_silver_transactions.sql).
    if not linha["amount"] > 0:
        raise EventoInvalido("valor_nao_positivo")
    if not customer_dob < transaction_ts.date():
        raise EventoInvalido("nascimento_apos_transacao")
    for campo, limite in (("customer_lat", 90), ("customer_long", 180),
                          ("merchant_lat", 90), ("merchant_long", 180)):
        if not -limite <= linha[campo] <= limite:
            raise EventoInvalido(f"fora_do_intervalo:{campo}")

    linha["published_at"] = _publicado_em(evento.get("published_at"))
    return linha


def _publicado_em(texto):
    """Horário em que o gerador publicou. Metadado: se vier torto, fica nulo."""
    try:
        return datetime.fromisoformat(texto).astimezone(timezone.utc)
    except (TypeError, ValueError):
        return None


def _timestamp(valor):
    return valor.strftime("%Y-%m-%d %H:%M:%S.%f+00:00") if valor else None


def para_bigquery(linha, processed_at, message_id):
    """Linha da silver.transactions_stream no formato de inserção do BigQuery."""
    return {
        **linha,
        "transaction_ts":    _timestamp(linha["transaction_ts"]),
        "customer_dob":      linha["customer_dob"].isoformat(),
        "published_at":      _timestamp(linha["published_at"]),
        "processed_at":      _timestamp(processed_at),
        "pubsub_message_id": message_id,
    }


def erro_para_bigquery(motivo, bruto, processed_at, message_id, transaction_id=None):
    """Linha da silver.transactions_stream_errors.

    O id vem do próprio evento; se ele não for JSON legível, do atributo da
    mensagem, passado em transaction_id.
    """
    texto = bruto.decode("utf-8", errors="replace") if isinstance(bruto, bytes) else str(bruto)
    try:
        transaction_id = json.loads(texto).get("trans_num") or transaction_id
    except (ValueError, AttributeError):
        pass
    return {
        "processed_at":      _timestamp(processed_at),
        "error_reason":      motivo,
        "transaction_id":    str(transaction_id) if transaction_id is not None else None,
        "raw_payload":       texto[:10_000],
        "pubsub_message_id": message_id,
    }
