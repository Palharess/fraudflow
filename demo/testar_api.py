"""Requisições da demonstração ao vivo: uma fraude, uma legítima e uma inválida.

As duas transações vêm da amostra de validação (api/teste/amostra.json, gerada
por api/scripts/gerar_amostra.sh): transações que o modelo não viu no treino.
O rótulo real só é mostrado depois da resposta, como na vida real.

Uso, da raiz do repositório:
    python3 demo/testar_api.py                 # API principal
    python3 demo/testar_api.py --contingencia  # API de contingência (ML.PREDICT)
"""
import json
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "api" / "scripts"))
from paridade_http import chamar, corpo_de  # noqa: E402

URLS = {
    "principal":    "https://fraudflow-api-189235868606.us-central1.run.app",
    "contingencia": "https://fraudflow-api-bq-189235868606.us-central1.run.app",
}
AMOSTRA = RAIZ / "api" / "teste" / "amostra.json"


def mostrar(titulo, corpo, url, rotulo=None):
    print(f"\n{'=' * 72}\n{titulo}\n{'=' * 72}")
    print("POST /v1/score")
    print(json.dumps(corpo, ensure_ascii=False))
    status, resposta, ms = chamar(f"{url}/v1/score", corpo)
    print(f"\n← {status} em {ms:.0f} ms (ida e volta, medido aqui)")
    print(json.dumps(resposta, indent=2, ensure_ascii=False))
    if rotulo is not None:
        print(f"\nRótulo real, revelado só agora: {'FRAUDE' if str(rotulo) == '1' else 'legítima'}")


def main():
    url = URLS["contingencia" if "--contingencia" in sys.argv else "principal"]
    if not AMOSTRA.is_file():
        sys.exit("Falta a amostra: rode antes  bash api/scripts/gerar_amostra.sh")
    linhas = json.loads(AMOSTRA.read_text())
    fraude = next(l for l in linhas if str(l["is_fraud"]) == "1")
    legitima = next(l for l in linhas if str(l["is_fraud"]) == "0")

    print(f"API: {url}")
    mostrar("1. Uma transação da janela de validação", corpo_de(fraude), url, fraude["is_fraud"])
    mostrar("2. Outra transação da janela de validação", corpo_de(legitima), url, legitima["is_fraud"])
    invalida = {**corpo_de(legitima), "amount": -5, "category": "crypto"}
    mostrar("3. Entrada inválida: valor negativo e categoria desconhecida", invalida, url)


if __name__ == "__main__":
    main()
