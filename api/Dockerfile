# API com o modelo exportado do BigQuery ML carregado no próprio container.
# Antes do build: bash scripts/baixar_modelo.sh (preenche api/modelo/).
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    MODELO_DIR=/app/modelo

WORKDIR /app

COPY requirements-local.txt .
RUN pip install --no-cache-dir -r requirements-local.txt

COPY app/ app/
COPY modelo/ modelo/

RUN useradd --create-home api
USER api

# O Cloud Run informa a porta pela variável PORT.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
