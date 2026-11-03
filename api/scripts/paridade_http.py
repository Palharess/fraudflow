"""Confere a API publicada por HTTP: mesmo score do ML.PREDICT, erro 422 para
entrada inválida e latência de ponta a ponta.

Roda no Cloud Shell, sem dependências além do Python:
    python3 scripts/paridade_http.py https://SERVICO.run.app teste/amostra.json

Termina com código 0 só se todas as verificações passarem.
"""
import json
import statistics
import sys
import time
import urllib.error
import urllib.request

TOLERANCIA = 1e-4
ESPERADO = 50


def chamar(url, corpo=None):
    """Faz a requisição e devolve (status, json, milissegundos)."""
    dados = json.dumps(corpo).encode() if corpo is not None else None
    pedido = urllib.request.Request(url, data=dados, headers={"Content-Type": "application/json"})
    inicio = time.perf_counter()
    try:
        with urllib.request.urlopen(pedido, timeout=60) as resposta:
            status, conteudo = resposta.status, json.load(resposta)
    except urllib.error.HTTPError as erro:
        status, conteudo = erro.code, json.load(erro)
    return status, conteudo, (time.perf_counter() - inicio) * 1000


def corpo_de(linha):
    return {
        "transaction_id": linha["transaction_id"],
        "transaction_ts": linha["transaction_ts"],
        "customer_dob":   linha["customer_dob"],
        "customer_lat":   float(linha["customer_lat"]),
        "customer_long":  float(linha["customer_long"]),
        "merchant_lat":   float(linha["merchant_lat"]),
        "merchant_long":  float(linha["merchant_long"]),
        "amount":         float(linha["amount"]),
        "category":       linha["category"],
        "city_pop":       int(linha["city_pop"]),
    }


def main(url, caminho):
    url = url.rstrip("/")
    linhas = json.loads(open(caminho).read())

    status_saude, saude, ms_saude = chamar(f"{url}/health")
    print(f"/health  {status_saude}  {ms_saude:.0f} ms  {saude}\n")

    respostas, tempos = [], []
    for linha in linhas:
        status, conteudo, ms = chamar(f"{url}/v1/score", corpo_de(linha))
        respostas.append((status, conteudo))
        tempos.append(ms)
    validas = [(l, c) for l, (s, c) in zip(linhas, respostas) if s == 200]
    diferencas = [abs(c["fraud_score"] - float(l["score_bq"])) for l, c in validas]
    ids_ok = all(c["transaction_id"] == l["transaction_id"] for l, c in validas)

    invalida = {**corpo_de(linhas[0]), "amount": 0}
    status_invalida, conteudo_invalida, _ = chamar(f"{url}/v1/score", invalida)

    print(f"backend: {validas[0][1]['backend'] if validas else '?'}")
    print(f"modelo:  {validas[0][1]['modelo'] if validas else '?'}\n")
    if diferencas:
        print(f"diferença máxima de score: {max(diferencas):.2e}")
    print("Latência HTTP de ponta a ponta, do Cloud Shell:")
    print(f"  primeira {tempos[0]:.0f} ms · mediana {statistics.median(tempos[1:]):.0f} ms · "
          f"pior {max(tempos[1:]):.0f} ms")
    print(f"Entrada inválida (amount = 0): {status_invalida} · {conteudo_invalida['detail'][0]['msg']}\n")

    verificacoes = {
        "/health respondeu 200": status_saude == 200,
        f"{ESPERADO} respostas 200": len(validas) == len(linhas) == ESPERADO,
        "transaction_id devolvido em cada resposta": ids_ok,
        f"diferença máxima < {TOLERANCIA:g}": bool(diferencas) and max(diferencas) < TOLERANCIA,
        "entrada inválida recusada com 422": status_invalida == 422,
    }
    for descricao, ok in verificacoes.items():
        print(f"  [{'ok' if ok else 'FALHOU'}] {descricao}")
    aprovado = all(verificacoes.values())
    print(f"\n{'API APROVADA' if aprovado else 'API REPROVADA'} · {url}")
    return 0 if aprovado else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
