# The embedding worker: sentence-transformers behind a small FastAPI app.
# n8n posts text, gets normalized vectors back, and writes them to
# postgres-vector itself; this service holds no state and never touches the
# database, so it can be swapped for something else without ceremony.
#
# Built here rather than pulled: there's no image for "this model, this
# API", and I'd rather not run a stranger's for something this small.
FROM python:3.12.15-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1

WORKDIR /app
# PyTorch's CPU build first, from its own index: grinder has no GPU, and
# PyPI's default torch drags in gigabytes of CUDA libraries it would never
# use. Pinned, so a rebuild can't quietly change the math under the stored
# embeddings. sentence-transformers then finds torch already there.
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch==2.14.1
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
