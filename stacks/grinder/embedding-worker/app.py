# Minimal embedding API for n8n. One model, loaded once at startup (loading is
# the slow part). bge-small-en-v1.5 by default: small enough for grinder's CPU,
# 384 dimensions, and good enough to start with. Not benchmarked; revisit if
# retrieval quality turns out to matter.
#
# No auth: nothing is published, only grinder_net can reach it.
import os

from fastapi import FastAPI
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer

MODEL_NAME = os.environ.get("EMBEDDING_MODEL", "BAAI/bge-small-en-v1.5")
model = SentenceTransformer(MODEL_NAME)

app = FastAPI(title="grinder embedding worker")


class EmbedRequest(BaseModel):
    texts: list[str]


class EmbedResponse(BaseModel):
    model: str
    dimensions: int
    embeddings: list[list[float]]


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_NAME}


@app.post("/embed", response_model=EmbedResponse)
def embed(req: EmbedRequest):
    vectors = model.encode(req.texts, normalize_embeddings=True).tolist()
    dims = len(vectors[0]) if vectors else 0
    return EmbedResponse(model=MODEL_NAME, dimensions=dims, embeddings=vectors)
