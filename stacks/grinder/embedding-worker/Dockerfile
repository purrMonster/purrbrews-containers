# Minimal CPU embedding service -- the "Index" step in
# edge-and-automation.md's second-brain pipeline: "embeddings + pgvector
# on CPU, always on. Only synthesis needs the 3080, via WoL." n8n calls
# this over HTTP for each document/chunk it wants embedded, and writes the
# resulting vector into postgres-vector itself (this service doesn't touch
# Postgres directly -- keeps it a stateless, swappable component).
#
# No published image exists for "the embedding model this project wants"
# -- sentence-transformers is the standard library for this, so this
# Dockerfile builds a small FastAPI wrapper around it rather than pulling
# a third-party image of unknown provenance for something this simple.
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Pre-download the model at build time, not first request -- so a fresh
# container doesn't stall its first real request on a multi-hundred-MB
# download, and so it works even if this node's internet is down when the
# container restarts.
ARG EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
ENV EMBEDDING_MODEL=${EMBEDDING_MODEL}
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('${EMBEDDING_MODEL}')"

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
