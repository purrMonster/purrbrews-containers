# llama-swap (local LLMs on roastery)

```
client → roastery:443 (Traefik) → Authelia → 127.0.0.1:9292 (llama-swap) → llama-server (one model at a time)
```

[llama-swap](https://github.com/mostlygeek/llama-swap) in Docker Desktop, on the
3080. It replaced Ollama on 2026-10-07 (runbook): the same llama.cpp underneath,
with every flag in view, an OpenAI-compatible API, Prometheus metrics, and
**profiles**, which is what game mode is built on.

## What clients ask for

| `model` | Normally | While a game runs |
|---|---|---|
| `assistant` | `gemma-4-12b`: Gemma 4 12B, Q4_K_M, GPU, 16k context | `qwen3.5-4b-cpu` |
| `fast` | `qwen3.5-9b`: Qwen3.5 9B, Q6_K, GPU, 32k context | `qwen3.5-4b-cpu` |
| `qwen3.5-4b-cpu` | Qwen3.5 4B, Q4_K_M, CPU only (4 threads), 8k context | the same |

Ask for `assistant` or `fast`, not a model's own ID. Those two names are
**profile pins**: [`../game-mode`](../game-mode/README.md) switches llama-swap
from the `normal` profile to `gaming` while a game runs. In `gaming`, the GPU
models' own IDs are pinned to the CPU model as well, so nothing can put a model
on the GPU mid-game.

The model choices were proposed 2026-10-07, not yet confirmed (runbook): swap
them in [`config/models.lock`](config/models.lock) and
[`config/config.yaml`](config/config.yaml) together.

## Why it's set up this way

- **One GPU model at a time, unloaded after 10 idle minutes.** 10 GB is the
  limit, the desktop takes some of it, and immich-ml shares the card. A game
  started later finds the VRAM free.
- **No `-ngl`.** llama-server's `--fit` (on by default) puts as many layers on
  the GPU as fit and the rest on the CPU, instead of failing to load when
  immich-ml or the desktop has taken some VRAM.
- **Flash attention with a q8_0 KV cache**, so the context costs half the
  memory, and every context size set explicitly.
- **The CPU model can't touch the GPU.** `CUDA_VISIBLE_DEVICES=-1` hides the
  card from its process. `-ngl 0` alone still lets llama.cpp put its CUDA
  context and large prompt batches on it.
- **No mixture-of-experts model (yet).** Keeping the experts in system RAM
  is how a 10 GB card runs 30B-class models. With 16 GB of RAM, half of which
  is Docker Desktop's VM limit by default, none of the current ones fit
  (Qwen3.6 35B-A3B is 22 GB at Q4). At 32 GB it becomes the first thing to try.
- **Models in a named volume** (`roastery-llm-models`), not a Windows folder:
  a bind mount into Docker Desktop's VM reads many times slower, and
  llama-server memory-maps the whole file. The volume lives in Docker's VM
  disk on C:, so a Docker Desktop reset or a Windows reinstall empties it, and
  `fetch-models` puts it back.
- **Loopback only, no API key.** It's published on `127.0.0.1:9292`; the way in
  from the LAN is Traefik plus Authelia, like Ollama before it.

## Bring-up

Docker Desktop with the WSL2 backend, and the GPU check from
[roastery's README](../README.md#immich-ml) passing first. Then, in
`stacks\roastery`:

```powershell
.\setup-secrets.ps1                              # .env.local, renders
.\compose.ps1 llama-swap run --rm fetch-models   # ~17 GB, verified against models.lock
.\compose.ps1 llama-swap up -d
```

`fetch-models` is safe to re-run: verified files are skipped, an interrupted
download resumes, a file with the wrong hash is thrown away. It lists, but
never deletes, model files no longer in `models.lock`.

Then Traefik (its [README](../traefik/README.md)), and
[game mode](../game-mode/README.md).

## Is it working?

1. `curl.exe http://127.0.0.1:9292/health` answers `OK`.
2. `curl.exe http://127.0.0.1:9292/v1/models` lists `assistant` and `fast`.
3. A chat:
   ```powershell
   curl.exe http://127.0.0.1:9292/v1/chat/completions -H "Content-Type: application/json" `
     -d '{\"model\":\"assistant\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'
   ```
   The first one takes a few seconds: the model loads.
4. While it answers, `nvidia-smi` shows `llama-server` holding most of the VRAM;
   ten minutes later it's gone.
5. `docker logs llama-swap` shows llama-server finding the 3080 (`CUDA0`), not
   falling back to the CPU.
6. From another machine, `roastery:9292` doesn't connect.
7. `http://127.0.0.1:9292/ui/` is llama-swap's own page: models, logs, the
   active profile. From the LAN it's `https://ollama.${DOMAIN}/ui/`, admins only.

## Changing things

- **A setting or a model:** edit `config/config.yaml`, then
  `.\compose.ps1 llama-swap restart` (the file is read once at start).
- **A new model file:** a line in `config/models.lock` (the file's comments
  say where the revision and hash come from), the model in `config.yaml`, a
  `gaming` pin for it if it's a GPU model, then `fetch-models` and a restart.
- **The image:** tag and digest together in `docker-compose.yml`, after
  llama-swap's CHANGELOG.

## Who talks to it

- **Through `ollama.${DOMAIN}`:** admins, and the `ollama_api_group` service
  accounts (Basic auth). The hostname kept its old name so nothing outside
  roastery had to change; it now speaks the OpenAI API (`/v1/...`), not
  Ollama's (`/api/tags` is gone).
- **grinder's Open WebUI: not connected.** It still points at Ollama's old
  `:11434`. The gap is the same one as before (Open WebUI's backend can't do
  the Authelia login); it's an open decision in the runbook, with options.
- **Home Assistant's voice pipeline (backlog):** needs an OpenAI-compatible
  conversation integration now, not the Ollama one.

## Later

- The CPU model moves to another node (not sieve) as a llama-swap **peer**:
  the `gaming` pins point at `<peer>/qwen3.5-4b-cpu`, and no client notices.
- Whisper (speech-to-text) for the ESP32 speakers is already in this image;
  it's one more entry in `config.yaml`.
