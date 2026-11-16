# Consuming llama-swap

Use llama-swap on roastery for local chat completions. Clients select an
OpenAI-compatible **Chat Completions** provider and send `assistant` or `fast`
as the model. The hostname still contains `ollama`, but the service no longer
speaks the Ollama API.

This guide describes the repository configuration checked on **2026-10-16**.
Live checks on **2026-10-16** confirmed a healthy local service, model listing
and successful completions through both aliases. The active `gaming` profile
routed both to Qwen3.5 4B CPU: each returned `hello` with `finish_reason: stop`
in about 9 seconds with a 512-token budget. Normal-profile GPU generation
and authenticated LAN access remain unverified. No Traefik process was seen.
The earlier sandboxed connection failure was not evidence of a stopped service;
the successful probes required access outside the sandbox.

## Connection settings

| Setting | On the roastery Windows host | From another LAN machine |
|---|---|---|
| Service root | `http://127.0.0.1:9292` | `https://ollama.${DOMAIN}` |
| API base URL | `http://127.0.0.1:9292/v1` | `https://ollama.${DOMAIN}/v1` |
| Authentication | None on loopback | Authelia; Basic auth for an approved service account |
| Model | `assistant` or `fast` | `assistant` or `fast` |

`${DOMAIN}` is a placeholder for the fleet domain. Replace it in client
settings; it is not part of the hostname. Append `/chat/completions` to the
API base once, giving `/v1/chat/completions`.

Port 9292 is published only on `127.0.0.1`. `http://roastery:9292` is not a
LAN endpoint. Inside a client container, `127.0.0.1` refers to that container,
not the Windows host. A containerized client needs a verified network path
to the authenticated HTTPS route. Do not assume a Docker host alias makes
the loopback-only port reachable.

## Authentication and remote access

The configured route is:

```text
LAN client → roastery:443 / Traefik → Authelia on percolator
                                   → 127.0.0.1:9292 / llama-swap
```

Traefik applies a LAN IP allowlist, then calls Authelia's
`/api/authz/forward-auth-basic`. Authelia has a `one_factor` rule for LLDAP
accounts in `ollama_api_group`. Other clients need the configured admin
login policy. A household login alone does not grant access.

For a service client, use HTTP Basic authentication with its approved LLDAP
username and password, over HTTPS. A bearer API key is not a substitute.
If a client only supports `Authorization: Bearer ...` and cannot send Basic
authentication, it is not directly compatible with this remote route.
The local endpoint itself does not require an API key; a client that insists
on one may accept a non-secret placeholder, but that does not authenticate
through Authelia.

Account creation, deployment of both proxy and auth configuration, and access
testing remain prerequisites. The owner chooses service-account names; this
guide creates none. Keep credentials in the consuming application's secret
store, outside source control.

The templates establish the intended route; they do not establish that it is
deployed or that Open WebUI has been configured to use it. Merely replacing
an old Ollama URL in a client will not complete that migration. The same
authentication policy covers `/ui/` and the control API; service-account
membership is not restricted to chat completions.

Tailscale or public access is not established by this configuration. The
allowlist explicitly contains the LAN subnet and loopback addresses. Verify
the network path before configuring an off-LAN consumer.

## Models and game mode

| Client model | Normal profile | Gaming profile | Configured context |
|---|---|---|---|
| `assistant` | `gemma-4-12b` | `qwen3.5-4b-cpu` | 16,384 normally; 8,192 gaming |
| `fast` | `qwen3.5-9b` | `qwen3.5-4b-cpu` | 32,768 normally; 8,192 gaming |

These are configured mappings, not benchmark results. Prefer the aliases so
the game-mode watcher can move requests to the CPU model. Both aliases use
the same model while gaming, and the GPU model IDs are also redirected.

Budget messages, tool definitions and output within the active context.
For requests that must work in either profile, keep the total below 8,192
tokens with room for the answer. A long conversation that fits the normal
profile may need truncation or summarization after a profile change.

The watcher checks every five seconds. After 60 seconds without a game, it
returns to `normal`. Starting a game unloads models and can interrupt work;
consumers should tolerate a failed request. A restart initially selects
`normal`, with the watcher reapplying `gaming` on its next poll.

## Endpoints

Paths below are relative to the **service root**, not the `/v1` base URL.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Check whether the proxy answers; does not prove a model can generate |
| GET | `/v1/models` | Inspect the available model IDs and aliases |
| POST | `/v1/chat/completions` | Submit chat messages |
| GET | `/api/profiles` | Read the active profile (`normal` or `gaming`) |
| GET | `/ui/` | Operator UI for models, profiles and logs |

`/api/profiles` is llama-swap's control API; it does not make this an Ollama
server. Do not use Ollama endpoints such as `/api/tags` or `/api/chat`.
Consumers should read the profile if needed and leave profile changes to
the watcher. Tool support is declared in the model configuration, but actual
tool-call behavior needs an integration test. Embeddings, vision, audio,
Responses API and structured-output support are not established by this guide.

## Quick start on roastery: PowerShell

Run on the Windows host, with llama-swap already running:

```powershell
$llmRoot = 'http://127.0.0.1:9292'
Invoke-RestMethod "$llmRoot/health" -TimeoutSec 10
Invoke-RestMethod "$llmRoot/v1/models" -TimeoutSec 10
Invoke-RestMethod "$llmRoot/api/profiles" -TimeoutSec 10

$body = @{
    model = 'assistant'
    messages = @(
        @{ role = 'user'; content = 'Reply with only the word hello.' }
    )
    max_tokens = 512
    stream = $false
} | ConvertTo-Json -Depth 6

$reply = Invoke-RestMethod -Method Post `
    -Uri "$llmRoot/v1/chat/completions" `
    -ContentType 'application/json' -Body $body -TimeoutSec 360
$reply.choices[0].message.content
```

The request loads a model and uses compute. A healthy proxy and a model list
are useful first checks, but only a successful completion verifies generation.
The local PowerShell request was tested with both aliases in the gaming profile.
The remote curl example still requires a deployed, authenticated HTTPS route.

## LAN client: curl with Basic authentication

First verify access without loading a model. In PowerShell, set the domain
and an existing approved service-account username when prompted:

```powershell
$llmDomain = Read-Host 'Fleet domain'
$llmUser = Read-Host 'Approved LLDAP service-account username'
$llmRoot = "https://ollama.$llmDomain"
curl.exe --fail-with-body --connect-timeout 10 --max-time 30 `
    --user "$llmUser" "$llmRoot/v1/models"
```

curl prompts for the password when only the username is supplied. Do not put
the password in the URL or command text. Keep certificate verification enabled.
Do not follow login redirects and treat the resulting HTML as API output.

For a completion, save the following as `request.json` in the consuming
project's working directory:

```json
{
  "model": "fast",
  "messages": [{"role": "user", "content": "Reply with only the word hello."}],
  "max_tokens": 512,
  "stream": false
}
```

Then run:

```powershell
curl.exe --fail-with-body --connect-timeout 10 --max-time 360 `
    --user "$llmUser" -H 'Content-Type: application/json' `
    --data-binary '@request.json' "$llmRoot/v1/chat/completions"
```

Read the answer from `choices[0].message.content`. Check the HTTP status and
error body before assuming that field exists. For streaming clients, request
`"stream": true` and handle server-sent events, including termination and
errors; test streaming through the deployed proxy before relying on it.

Allow output budget for reasoning as well as the visible answer. Live tests
with `max_tokens: 64` returned empty content and `finish_reason: length` for
both aliases; the model used the budget before reaching its final answer.
With 512 allowed, the tested requests completed in 102 and 109 output tokens.
If content is empty, inspect `finish_reason` before treating it as success.

## Timeouts, capacity and retries

One model runs at a time in this configuration. Each llama-server has one
parallel slot (`-np 1`); batch consumers should start with one in-flight request
and avoid alternating aliases unnecessarily. Model switching and cold starts
add latency. GPU models unload after 600 idle seconds; the CPU model after 300.

The model health-check timeout is 300 seconds. The examples allow 360 seconds
for a small completion, as a starting client setting rather than a response
time guarantee. CPU generation or larger outputs may need a larger deadline.

Use bounded retries with backoff for temporary connection or server failures.
Do not retry authentication errors, unknown models or oversized contexts
unchanged. A timeout does not prove the server stopped generating. Do not
blindly repeat tool execution or other external side effects after a retry.

## Troubleshooting

| Symptom | What to check |
|---|---|
| Local connection refused | Docker Desktop and the llama-swap container; confirm the host and port |
| LAN port 9292 fails | Expected: use the authenticated HTTPS route |
| HTTPS connection refused | Native Traefik, DNS and the Windows firewall on roastery |
| Redirect, login HTML or 401 | Missing or rejected authentication; confirm Basic auth and the service account |
| 403 | LAN allowlist, account groups and Authelia policy |
| 502/503 or model-load failure | Proxy/backend logs, model files and available resources |
| Invalid model | Read `/v1/models`; select `assistant` or `fast` |
| Context error after gaming starts | Reduce messages and output budget for the 8,192-token CPU context |
| Slow first answer | Cold load, model swap or CPU profile; inspect `/api/profiles` |

Read-only host checks include `docker ps --filter name=llama-swap` and
`docker logs --tail 100 llama-swap`. Review logs locally before sharing them.
Service restarts, firewall edits and auth-policy changes are separate operator
actions requiring the owner's go-ahead under the repository rules.

## Configuration references

- [Port binding and container](../stacks/roastery/llama-swap/docker-compose.yml)
- [Models, aliases, context and timeouts](../stacks/roastery/llama-swap/config/config.yaml)
- [LAN route and authentication middleware](../stacks/roastery/traefik/config/dynamic/llama-swap.yml.template)
- [Authelia authentication and access policy](../stacks/percolator/authelia/config/configuration.yml.template)
- [Service bring-up](../stacks/roastery/llama-swap/README.md)
- [Traefik bring-up](../stacks/roastery/traefik/README.md)
- [Game-mode watcher](../stacks/roastery/game-mode/README.md)
- [Deployment history and pending work](../runbook.md)
