"""Confere, dentro da imagem da API, se o modelo carregado reproduz o ML.PREDICT.

Roda no container, com scripts/ e teste/ montados (ver api/README.md):
    python scripts/paridade.py /teste/amostra.json

Termina com código 0 só se todas as verificações passarem.
"""
import json
import math
import statistics
import sys
import time
from datetime import date, datetime, timezone
from pathlib import Path

from app.modelo import ModeloLocal

TOLERANCIA = 1e-4
ESPERADO = 50
DIRETORIO_MODELO = Path("/app/modelo")

# Candidatos para o TIMESTAMP na entrada do TRANSFORM. O formato só é aceito se
# o score bater com o ML.PREDICT: um fuso errado não dá erro, só muda a hora.
FORMATOS_TS = {
    "texto simples": "%Y-%m-%d %H:%M:%S",
    "com +00":       "%Y-%m-%d %H:%M:%S+00",
    "com UTC":       "%Y-%m-%d %H:%M:%S UTC",
    "ISO com Z":     "%Y-%m-%dT%H:%M:%SZ",
}


def carregar(caminho):
    linhas = json.loads(Path(caminho).read_text())
    transacoes = [{
        "transaction_ts": datetime.strptime(l["transaction_ts"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc),
        "customer_dob":   date.fromisoformat(l["customer_dob"]),
        "customer_lat":   float(l["customer_lat"]),
        "customer_long":  float(l["customer_long"]),
        "merchant_lat":   float(l["merchant_lat"]),
        "merchant_long":  float(l["merchant_long"]),
        "amount":         float(l["amount"]),
        "category":       l["category"],
        "city_pop":       int(l["city_pop"]),
    } for l in linhas]
    referencia = [float(l["score_bq"]) for l in linhas]
    return linhas, transacoes, referencia


def mostrar_transform(modelo, transacao):
    """Assinatura do TRANSFORM e as features que ele gera para uma transação."""
    import tensorflow as tf

    funcao = tf.saved_model.load(str(DIRETORIO_MODELO / "transform")).signatures["serving_default"]
    entradas = funcao.structured_input_signature[1]
    print("Entradas do TRANSFORM:")
    for nome, spec in sorted(entradas.items()):
        print(f"  {nome:<16} {spec.dtype.name}")
    instancia = modelo.entrada(transacao)
    saida = funcao(**{nome: tf.constant([instancia[nome]], spec.dtype) for nome, spec in entradas.items()})
    print("\nFeatures geradas para a primeira transação:")
    for nome, tensor in sorted(saida.items()):
        print(f"  {nome:<16} {tensor.numpy()[0]!r}")
    print(f"\nSaída crua do Predictor:\n  {modelo._predictor.predict([instancia])[0]}\n")


def main(caminho):
    linhas, transacoes, referencia = carregar(caminho)
    modelo = ModeloLocal(DIRETORIO_MODELO)
    print(f"modelo: {modelo.versao}\n")
    try:
        mostrar_transform(modelo, transacoes[0])
    except Exception as erro:
        # Só diagnóstico: não impede o teste dos formatos abaixo.
        print(f"Não foi possível mostrar o TRANSFORM: {erro}\n")

    escolhido, scores = None, None
    for nome, formato in FORMATOS_TS.items():
        modelo.formato_ts = formato
        try:
            candidatos = modelo.pontuar(transacoes)
        except Exception as erro:
            print(f"{nome:<14} recusado: {str(erro)[:300]}")
            continue
        diferenca = max(abs(s - r) for s, r in zip(candidatos, referencia))
        print(f"{nome:<14} aceito   diferença máxima {diferenca:.2e}")
        if diferenca < TOLERANCIA and escolhido is None:
            escolhido, scores = nome, candidatos

    print()
    verificacoes = {
        f"{ESPERADO} transações na amostra": len(transacoes) == ESPERADO,
        "fraudes e legítimas presentes": {str(l["is_fraud"]) for l in linhas} == {"0", "1"},
        "algum formato de TIMESTAMP bateu": escolhido is not None,
    }
    if scores is not None:
        diferencas = [abs(s - r) for s, r in zip(scores, referencia)]
        verificacoes["scores finitos entre 0 e 1"] = all(math.isfinite(s) and 0 <= s <= 1 for s in scores)
        verificacoes[f"diferença máxima < {TOLERANCIA:g}"] = max(diferencas) < TOLERANCIA

        print(f"formato escolhido: {escolhido} ({FORMATOS_TS[escolhido]!r})")
        print(f"diferença máxima:  {max(diferencas):.2e}\n")
        print("Maiores diferenças:")
        piores = sorted(range(len(scores)), key=lambda i: -diferencas[i])[:5]
        for i in piores:
            print(f"  {linhas[i]['transaction_ts']}  {linhas[i]['category']:<14} "
                  f"rótulo {linhas[i]['is_fraud']}  bq {referencia[i]:.6f}  local {scores[i]:.6f}")

        modelo.formato_ts = FORMATOS_TS[escolhido]
        tempos = []
        for transacao in transacoes:
            inicio = time.perf_counter()
            modelo.pontuar([transacao])
            tempos.append((time.perf_counter() - inicio) * 1000)
        print(f"\nLatência da inferência, uma transação por vez, sem HTTP:")
        print(f"  primeira {tempos[0]:.1f} ms · mediana {statistics.median(tempos[1:]):.1f} ms · "
              f"pior {max(tempos[1:]):.1f} ms")

    print()
    for descricao, ok in verificacoes.items():
        print(f"  [{'ok' if ok else 'FALHOU'}] {descricao}")
    aprovado = all(verificacoes.values())
    print(f"\n{'PARIDADE CONFIRMADA' if aprovado else 'PARIDADE NÃO CONFIRMADA'} · {modelo.versao}")
    return 0 if aprovado else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
