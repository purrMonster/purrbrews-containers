# litellm

The fleet's one door to a cloud model, on grinder. It stands in for the local
LLMs that ran on roastery until the 2026-11 rebuild (`runbook.md`, 2026-11-16).

| | |
|---|---|
| On this node | `http://litellm:4000/v1` on the `proxy` network (Open WebUI uses this) |
| From other machines | `https://llm.${DOMAIN}/v1`, LAN only, Basic auth as a service account in `llm_api_group` |
| Model name to ask for | `default` |
| Data | none: no database, nothing to back up |

## Before the first up

1. Pick the provider and model, and make an API key for this fleet only, with
   a spending limit. Not chosen yet (runbook, 2026-11-17): any endpoint that
   speaks the OpenAI API works, OpenAI's own included.
2. `./setup-secrets.sh` on grinder asks for the endpoint's base URL (ending in
   `/v1`), the model id as that endpoint knows it, and the key.
3. In LLDAP, the service accounts that call it from other machines go in
   `llm_api_group` and nowhere else (pourOver's account is one).
4. `./compose.sh litellm up -d --wait`.

## Is it working?

```bash
# on grinder: LiteLLM itself
sudo docker exec litellm python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:4000/health/liveliness').read())"
# from another node: the route, the certificate and Authelia (expect 401 without credentials)
curl -sI https://llm.${DOMAIN}/health/liveliness | head -1
```

Then one real request from Open WebUI (`chat.${DOMAIN}`): the model list should
show `default`, and a message should get an answer.

## Not checked yet

Written 2026-11-16 and not yet run on a node. Check on first bring-up:

- the container turns healthy and Open WebUI lists `default`;
- pourOver's requests, which were written for llama-swap, are accepted by the
  cloud model (`drop_params` removes options the provider doesn't know);
- the provider bills only what the fleet sends: look at its usage page after a day.

## Changing provider or model

Delete the lines that change from `secrets.env.local` (`LLM_UPSTREAM_MODEL`;
for a new provider also `LLM_UPSTREAM_API_BASE` and `LLM_UPSTREAM_API_KEY`), run
`./setup-secrets.sh`, then `./compose.sh litellm up -d --force-recreate`. No
other app changes.

A provider without an OpenAI-compatible API needs LiteLLM's own prefix for it
in `config/config.yaml.template` instead of `openai/`, and usually no `api_base`.
