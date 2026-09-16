# Minimal embedding API for n8n to call. One model, loaded once at
# startup (not per-request -- sentence-transformers' load is the slow
# part). BAAI/bge-small-en-v1.5 is the default: small enough to run
# comfortably on grinder's 2c/4t CPU (infrastructure.md §2), 384-dim
# output, competitive retrieval quality for a home corpus at this scale --
# not benchmarked against alternatives here, a reasonable default to start
# from and revisit if retrieval quality turns out to matter.
#
# No auth -- this API is reachable only from grinder_net (see
# docker-compose.yml, no ports published), same trust model as every
# other container-to-container call in this fleet.
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
