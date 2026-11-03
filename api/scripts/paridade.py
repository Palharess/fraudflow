"""Confere, dentro da imagem da API, se o modelo carregado reproduz o BigQuery.

Duas comparações, nas mesmas 50 transações:
  1. features: o TRANSFORM local contra o ML.TRANSFORM (colunas f_* da amostra);
  2. score: o modelo local contra o ML.PREDICT.

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
FEATURES = ("amount", "log_amount", "category", "hour", "day_of_week",
            "is_night", "age", "distance_km", "city_pop")
CATEGORICAS = {"category", "is_night"}

# Candidatos para o TIMESTAMP na entrada do TRANSFORM. O formato só é aceito se
# o score bater com o ML.PREDICT: um fuso errado não dá erro, só muda a hora.
FORMATOS_TS = {
    "com +00":       "%Y-%m-%d %H:%M:%S+00",
    "texto simples": "%Y-%m-%d %H:%M:%S",
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


def comparar_features(modelo, linhas, transacoes):
    """Diferença de cada feature entre o TRANSFORM local e o ML.TRANSFORM."""
    locais = modelo.features(transacoes)
    print(f"Features da primeira transação (local): {locais[0]}\n")
    com_referencia = [i for i, l in enumerate(linhas) if l.get("f_amount") is not None]
    print(f"Features comparadas com o ML.TRANSFORM em {len(com_referencia)} de {len(linhas)} transações:")
    iguais = True
    for nome in FEATURES:
        if nome in CATEGORICAS:
            erros = sum(str(locais[i][nome]).lower() != str(linhas[i][f"f_{nome}"]).lower()
                        for i in com_referencia)
            print(f"  {nome:<12} {erros} diferentes")
            iguais &= erros == 0
        else:
            diferenca = max((abs(float(locais[i][nome]) - float(linhas[i][f"f_{nome}"]))
                             for i in com_referencia), default=0.0)
            print(f"  {nome:<12} diferença máxima {diferenca:.2e}")
            iguais &= diferenca < 1e-6
    print()
    return iguais and len(com_referencia) == len(linhas)


def main(caminho):
    linhas, transacoes, referencia = carregar(caminho)
    modelo = ModeloLocal(DIRETORIO_MODELO)
    print(f"modelo: {modelo.versao}\n")

    print("Entradas do TRANSFORM:")
    for nome, spec in sorted(modelo._entradas.items()):
        print(f"  {nome:<16} {spec.dtype.name}")
    print()

    escolhido, scores = None, None
    for nome, formato in FORMATOS_TS.items():
        modelo.formato_ts = formato
        try:
            candidatos = modelo.pontuar(transacoes)
        except Exception as erro:
            print(f"{nome:<14} recusado: {str(erro).splitlines()[-1][:200]}")
            continue
        diferenca = max(abs(s - r) for s, r in zip(candidatos, referencia))
        print(f"{nome:<14} aceito   diferença máxima {diferenca:.2e}")
        if diferenca < TOLERANCIA and escolhido is None:
            escolhido, scores = nome, candidatos
    print()

    # As features são comparadas no formato escolhido ou, se nenhum bateu, no
    # primeiro candidato, para mostrar onde está a diferença.
    modelo.formato_ts = FORMATOS_TS[escolhido or next(iter(FORMATOS_TS))]
    try:
        features_iguais = comparar_features(modelo, linhas, transacoes)
    except Exception as erro:
        print(f"Não foi possível comparar as features: {erro}\n")
        features_iguais = False

    verificacoes = {
        f"{ESPERADO} transações na amostra": len(transacoes) == ESPERADO,
        "fraudes e legítimas presentes": {str(l["is_fraud"]) for l in linhas} == {"0", "1"},
        "features iguais às do ML.TRANSFORM": features_iguais,
        "algum formato de TIMESTAMP bateu": escolhido is not None,
    }
    if scores is not None:
        diferencas = [abs(s - r) for s, r in zip(scores, referencia)]
        verificacoes["scores finitos entre 0 e 1"] = all(math.isfinite(s) and 0 <= s <= 1 for s in scores)
        verificacoes[f"diferença máxima < {TOLERANCIA:g}"] = max(diferencas) < TOLERANCIA

        print(f"formato escolhido: {escolhido} ({FORMATOS_TS[escolhido]!r})")
        print(f"diferença máxima de score: {max(diferencas):.2e}\n")
        print("Maiores diferenças:")
        for i in sorted(range(len(scores)), key=lambda i: -diferencas[i])[:5]:
            print(f"  {linhas[i]['transaction_ts']}  {linhas[i]['category']:<14} "
                  f"rótulo {linhas[i]['is_fraud']}  bq {referencia[i]:.6f}  local {scores[i]:.6f}")

        tempos = []
        for transacao in transacoes:
            inicio = time.perf_counter()
            modelo.pontuar([transacao])
            tempos.append((time.perf_counter() - inicio) * 1000)
        print("\nLatência da inferência, uma transação por vez, sem HTTP:")
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
