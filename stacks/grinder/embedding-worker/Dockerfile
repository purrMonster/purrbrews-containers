# The embedding worker: sentence-transformers behind a small FastAPI app.
# n8n posts text, gets normalized vectors back, and writes them to
# postgres-vector itself; this service holds no state and never touches the
# database, so it can be swapped for something else without ceremony.
#
# Built here rather than pulled: there's no image for "this model, this
# API", and I'd rather not run a stranger's for something this small.
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# The model is downloaded at build time, so the first request doesn't wait on
# a few hundred MB and a restart works with the internet down.
ARG EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
ENV EMBEDDING_MODEL=${EMBEDDING_MODEL}
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('${EMBEDDING_MODEL}')"

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
