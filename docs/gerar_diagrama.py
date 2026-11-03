"""Gera docs/arquitetura.svg e docs/arquitetura.png a partir da mesma geometria.

Uso: python docs/gerar_diagrama.py   (requer Pillow)
"""
import sys
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image, ImageDraw, ImageFont

SAIDA = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent
SAIDA.mkdir(parents=True, exist_ok=True)

L, A = 1320, 600
TINTA, CINZA = "#1f2933", "#52606d"

# Faixas: (x, y, w, h, título, cor de fundo, cor do título)
FAIXAS = [
    (15, 40, 1050, 150, "CAMADA BATCH · histórico (Trabalho 1)", "#e8f0fe", "#1a56db"),
    (15, 245, 1050, 215, "CAMADA STREAMING · tempo real (Trabalho 2)", "#e6f6ec", "#0e7a3d"),
    (1085, 40, 220, 545, "SERVIÇO (Trabalho 2)", "#fff4e0", "#b45309"),
]

# Caixas: nome → (x, y, w, h, linha 1, linha 2, destaque)
CAIXAS = {
    "raw":      (30, 95, 175, 62, "Cloud Storage", "raw/train/fraudTrain.csv", False),
    "bronze":   (240, 95, 175, 62, "bronze.transactions", "load job · texto, como chegou", False),
    "silver":   (450, 95, 175, 62, "silver.transactions", "tipada, limpa, sem duplicatas", False),
    "gold":     (660, 95, 175, 62, "gold.ml_input", "entrada do modelo", False),
    "bqml":     (870, 95, 175, 62, "BigQuery ML", "fraud_boosted + TRANSFORM", True),
    "holdout":  (30, 320, 175, 62, "Cloud Storage", "holdout/fraudTest.csv", False),
    "pubsub":   (240, 320, 175, 62, "Pub/Sub", "gerador → tópico transactions", True),
    "dataflow": (450, 320, 175, 62, "Dataflow", "Apache Beam · limpeza", True),
    "stream":   (660, 285, 175, 58, "silver.", "transactions_stream", False),
    "erros":    (660, 375, 175, 58, "silver.transactions_", "stream_errors (+ motivo)", False),
    "view":     (870, 285, 175, 62, "gold.vw_transactions_", "unified · batch + stream", True),
    "registry": (1105, 80, 180, 58, "Vertex AI", "Model Registry", False),
    "export":   (1105, 170, 180, 58, "Cloud Storage", "EXPORT MODEL · artefato", False),
    "api":      (1105, 285, 180, 62, "Cloud Run · fraudflow-api", "modelo no container", True),
    "apibq":    (1105, 385, 180, 62, "Cloud Run · api-bq", "ML.PREDICT (contingência)", False),
    "cliente":  (870, 500, 175, 52, "Cliente HTTP", "POST /v1/score", False),
}


def lado(nome, onde):
    x, y, w, h, *_ = CAIXAS[nome]
    return {"e": (x, y + h / 2), "d": (x + w, y + h / 2), "c": (x + w / 2, y), "b": (x + w / 2, y + h)}[onde]


# Setas: (pontos, rótulo, posição do rótulo, tracejada)
SETAS = [
    ([lado("raw", "d"), lado("bronze", "e")], "", None, False),
    ([lado("bronze", "d"), lado("silver", "e")], "", None, False),
    ([lado("silver", "d"), lado("gold", "e")], "", None, False),
    ([lado("gold", "d"), lado("bqml", "e")], "", None, False),
    ([lado("holdout", "d"), lado("pubsub", "e")], "", None, False),
    ([lado("pubsub", "d"), lado("dataflow", "e")], "", None, False),
    ([lado("dataflow", "d"), (642, 351), (642, 314), lado("stream", "e")], "válidas", (612, 306), False),
    ([lado("dataflow", "d"), (642, 351), (642, 404), lado("erros", "e")], "recusadas", (605, 420), False),
    ([lado("stream", "d"), lado("view", "e")], "", None, False),
    ([lado("silver", "b"), (537, 222), (957, 222), lado("view", "c")], "o histórico também entra na view", (747, 214), False),
    ([lado("bqml", "d"), (1070, 126), (1070, 109), lado("registry", "e")], "", None, False),
    ([lado("bqml", "d"), (1070, 126), (1070, 199), lado("export", "e")], "", None, False),
    ([lado("export", "b"), lado("api", "c")], "imagem Docker", (1245, 262), False),
    ([lado("cliente", "c"), (957, 470), (1060, 470), (1060, 316), lado("api", "e")], "", None, False),
    ([lado("cliente", "d"), (1080, 526), (1080, 470), (1195, 470), lado("apibq", "b")], "URL alternativa (troca manual)", (1195, 500), True),
]

# ------------------------------------------------------------------ SVG
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{L}" height="{A}" viewBox="0 0 {L} {A}" '
       f'font-family="Arial, Helvetica, sans-serif">',
       '<defs><marker id="p" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
       f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{CINZA}"/></marker></defs>',
       f'<rect width="{L}" height="{A}" fill="#ffffff"/>',
       f'<text x="15" y="26" font-size="18" font-weight="bold" fill="{TINTA}">FraudFlow · arquitetura híbrida batch + streaming</text>']
for x, y, w, h, titulo, fundo, cor in FAIXAS:
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{fundo}"/>')
    svg.append(f'<text x="{x + 12}" y="{y + 22}" font-size="13" font-weight="bold" fill="{cor}">{escape(titulo)}</text>')
for pontos, rotulo, pos, tracejada in SETAS:
    caminho = " ".join(f"{px:.0f},{py:.0f}" for px, py in pontos)
    estilo = ' stroke-dasharray="6 4"' if tracejada else ""
    svg.append(f'<polyline points="{caminho}" fill="none" stroke="{CINZA}" stroke-width="1.6"{estilo} marker-end="url(#p)"/>')
    if rotulo:
        if pos is None:
            (x1, y1), (x2, y2) = pontos[0], pontos[1]
            pos = ((x1 + x2) / 2, y1 - 7)
        svg.append(f'<text x="{pos[0]:.0f}" y="{pos[1]:.0f}" font-size="11" text-anchor="middle" fill="{CINZA}">{escape(rotulo)}</text>')
for x, y, w, h, l1, l2, destaque in CAIXAS.values():
    borda = TINTA if destaque else "#9aa5b1"
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="7" fill="#ffffff" stroke="{borda}" '
               f'stroke-width="{2 if destaque else 1.2}"/>')
    svg.append(f'<text x="{x + w / 2:.0f}" y="{y + h / 2 - 4:.0f}" font-size="13" font-weight="bold" '
               f'text-anchor="middle" fill="{TINTA}">{escape(l1)}</text>')
    svg.append(f'<text x="{x + w / 2:.0f}" y="{y + h / 2 + 14:.0f}" font-size="11" text-anchor="middle" '
               f'fill="{CINZA}">{escape(l2)}</text>')
svg.append("</svg>")
(SAIDA / "arquitetura.svg").write_text("\n".join(svg), encoding="utf-8")

# ------------------------------------------------------------------ PNG
E = 2  # escala, para a imagem ficar nítida no PDF
img = Image.new("RGB", (L * E, A * E), "white")
d = ImageDraw.Draw(img)
FONTES = {False: ["C:/Windows/Fonts/arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"],
          True: ["C:/Windows/Fonts/arialbd.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]}


def fonte(tam, negrito=False):
    caminho = next(p for p in FONTES[negrito] if Path(p).is_file())
    return ImageFont.truetype(caminho, tam * E)
s = lambda *v: [c * E for c in v]


def seta(pontos, tracejada):
    pts = [(px * E, py * E) for px, py in pontos]
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        if tracejada:
            comprimento = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
            passos = int(comprimento // (10 * E))
            for i in range(0, passos, 1):
                if i % 2 == 0:
                    a, b = i / max(passos, 1), min((i + 1) / max(passos, 1), 1)
                    d.line([(x1 + (x2 - x1) * a, y1 + (y2 - y1) * a), (x1 + (x2 - x1) * b, y1 + (y2 - y1) * b)],
                           fill=CINZA, width=int(1.6 * E))
        else:
            d.line([(x1, y1), (x2, y2)], fill=CINZA, width=int(1.6 * E))
    (x1, y1), (x2, y2) = pts[-2], pts[-1]
    comprimento = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5 or 1
    ux, uy = (x2 - x1) / comprimento, (y2 - y1) / comprimento
    t = 9 * E
    d.polygon([(x2, y2), (x2 - ux * t - uy * t / 2, y2 - uy * t + ux * t / 2),
               (x2 - ux * t + uy * t / 2, y2 - uy * t - ux * t / 2)], fill=CINZA)


d.text((15 * E, 12 * E), "FraudFlow · arquitetura híbrida batch + streaming", font=fonte(18, True), fill=TINTA)
for x, y, w, h, titulo, fundo, cor in FAIXAS:
    d.rounded_rectangle(s(x, y, x + w, y + h), radius=10 * E, fill=fundo)
    d.text(((x + 12) * E, (y + 9) * E), titulo, font=fonte(13, True), fill=cor)
for pontos, rotulo, pos, tracejada in SETAS:
    seta(pontos, tracejada)
    if rotulo:
        if pos is None:
            (x1, y1), (x2, y2) = pontos[0], pontos[1]
            pos = ((x1 + x2) / 2, y1 - 7)
        d.text((pos[0] * E, pos[1] * E), rotulo, font=fonte(11), fill=CINZA, anchor="ms")
for x, y, w, h, l1, l2, destaque in CAIXAS.values():
    d.rounded_rectangle(s(x, y, x + w, y + h), radius=7 * E, fill="white",
                        outline=TINTA if destaque else "#9aa5b1", width=int((2 if destaque else 1.2) * E))
    d.text(((x + w / 2) * E, (y + h / 2 - 4) * E), l1, font=fonte(13, True), fill=TINTA, anchor="ms")
    d.text(((x + w / 2) * E, (y + h / 2 + 14) * E), l2, font=fonte(11), fill=CINZA, anchor="ms")
img.save(SAIDA / "arquitetura.png", optimize=True)
print("ok", SAIDA)
