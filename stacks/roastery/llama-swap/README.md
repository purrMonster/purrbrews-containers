# llama-swap (local LLMs on roastery)

```
client → roastery:443 (Traefik) → Authelia → 127.0.0.1:9292 (llama-swap) → llama-server (one model at a time)
```

[llama-swap](https://github.com/mostlygeek/llama-swap) in Docker Desktop, on the
3080. It replaced Ollama on 2026-10-07 (runbook): the same llama.cpp underneath,
with every flag in view, an OpenAI-compatible API, Prometheus metrics, and
**profiles**, which is what game mode is built on.

API base on the Windows host: `http://127.0.0.1:9292/v1`. The configured LAN
base is `https://ollama.${DOMAIN}/v1`, through Traefik and Authelia. See the
[consumer guide](../../../docs/llama-swap-consumption.md) for client settings,
Basic authentication, request examples and troubleshooting.

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

These mappings are configured in [`config/config.yaml`](config/config.yaml).
On 2026-10-16, both aliases successfully returned a completion in the `gaming`
profile using Qwen3.5 4B CPU. Normal-profile GPU generation remains unverified
in that check. Change model files in [`config/models.lock`](config/models.lock)
and `config.yaml` together. Both aliases have an 8,192-token context while
gaming, so budget messages, tools and output for that smaller limit.

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
3. A chat (loads the selected model):
   ```powershell
   $body = @{
       model = 'assistant'
       messages = @(@{ role = 'user'; content = 'Reply with only the word hello.' })
       max_tokens = 512
       stream = $false
   } | ConvertTo-Json -Depth 6
   $reply = Invoke-RestMethod -Method Post `
       -Uri 'http://127.0.0.1:9292/v1/chat/completions' `
       -ContentType 'application/json' -Body $body -TimeoutSec 360
   $reply.choices[0].message.content
   ```
   A cold load adds latency. The 2026-10-16 CPU checks returned `hello` through
   both aliases in about nine seconds. A 64-token limit produced empty content
   with `finish_reason: length`; allow room for reasoning and the final answer.
4. `curl.exe http://127.0.0.1:9292/api/profiles` reports the active profile.
   In `normal`, check `nvidia-smi` and the model logs for GPU use. In `gaming`,
   CPU-only inference is expected; do not switch profiles just to test the GPU.
5. `docker logs --tail 100 llama-swap` shows model loading or errors. GPU
   models unload after ten idle minutes; the CPU model after five.
6. From another machine, `roastery:9292` doesn't connect.
7. `http://127.0.0.1:9292/ui/` is llama-swap's own page: models, logs, the
   active profile. From the LAN it's `https://ollama.${DOMAIN}/ui/`, under the
   same LAN allowlist and Authelia policy as the API (admins or authorized
   `ollama_api_group` accounts; there is no separate UI-only restriction).

The 2026-10-16 check confirmed local health, model listing and gaming-profile
generation. No Traefik process was seen and the HTTPS probe failed; remote
access is not yet verified. Sandbox connection failures alone do not establish
that the service is down: these local checks succeeded outside the sandbox.

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
  `:11434`. The proxy templates now support Basic auth for `ollama_api_group`;
  deployment and client migration still need verification. Use an
  OpenAI-compatible connection that can send Basic authentication. A bearer
  API-key field alone does not authenticate through this route.
- **Home Assistant's voice pipeline (backlog):** needs an OpenAI-compatible
  conversation integration now, not the Ollama one.

## Later

- The CPU model moves to another node (not sieve) as a llama-swap **peer**:
  the `gaming` pins point at `<peer>/qwen3.5-4b-cpu`, and no client notices.
- Whisper (speech-to-text) for the ESP32 speakers is already in this image;
  it's one more entry in `config.yaml`.
