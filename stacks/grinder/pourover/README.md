# pourOver

Text a task in meowGram; it lands in Vikunja, filed properly. A local model on roastery
turns the message into a plan, pourOver checks it and files it with the sender's own Vikunja
token, and replies. Vikunja does everything after that: reminders (CalDAV to the phones),
repeats, sharing. Source, design and tests: [purrMonster/pourOver](https://github.com/purrMonster/pourOver).

Optional on grinder: `fleet.py deploy grinder` leaves it out unless asked
(`--include-optional pourover`).

| | |
|---|---|
| Image | `ghcr.io/purrmonster/pourover`, pinned by tag and digest, published by pourOver's release workflow |
| Port | `:8790` → 8000, for Gatus on sieve only (`./firewall`) |
| Talks to | Vikunja (percolator), llama-swap via `ollama.${DOMAIN}` (roastery), ntfy (sieve), meowGram's bot API once it exists |
| Data | `/srv/data/pourover/pourover.db` (SQLite, WAL): command log, pending confirms, queue, meowGram cursor |

## Before the first up

1. **LLM service account.** LLDAP UI → create a service account (a cat-breed name of the
   owner's choosing; its job is "pourOver's model login") with a long password, member of
   `ollama_api_group` only. Authelia already lets that group through to `ollama.${DOMAIN}`
   with Basic auth.
2. **Vikunja token per person.** Each person signs in to Vikunja → Settings → API tokens →
   new token with tasks, projects and labels (read and write). Note their user id too.
3. **Optional: ntfy.** A topic per person and a token that may write it (sieve's ntfy).
   Blank skips ntfy; replies still come back in meowGram.
4. **meowGram:** leave its four questions blank until meowGram's bot API ships. Without it
   pourOver runs and answers `/inbound`, but nobody can text it yet.

## Bring-up

As `barista` in `/opt/purrbrews/stacks/grinder`, on a reviewed commit:

```bash
./setup-secrets.sh                 # asks the pourOver questions, renders config/users.yaml
sudo ./firewall.sh                 # the Gatus rule
./compose.sh pourover up -d --wait
```

## Is it working?

```bash
curl -s localhost:8790/healthz                       # {"status":"ok","db":true}
sudo docker logs pourover --tail 20                  # no "meowgram" thread while its URL is blank
. pourover/secrets.env.local
curl -s localhost:8790/inbound -H "X-Pourover-Token: $POUROVER_INBOUND_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"sender\":\"$POUROVER_USER_A_MEOWGRAM\",\"text\":\"what's due today\"}"
```

The last one reads Vikunja as person A and lists their tasks without changing anything.
Then one write, which proves the model path end to end (roastery must be awake):

```bash
curl -s localhost:8790/inbound -H "X-Pourover-Token: $POUROVER_INBOUND_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"sender\":\"$POUROVER_USER_A_MEOWGRAM\",\"text\":\"pourover test task tomorrow 9am\"}"
```

The reply names the project, the due time and the reminder; the task is in Vikunja with the
`pourover` label. Remove it with `undo` (same call, text `undo`, then `yes`).

## Things worth knowing

- **roastery asleep or gaming:** messages that need the model wait in the queue (6 h), a
  message with a time goes straight to Inbox, and queued results arrive on ntfy.
- **401 from the model** means the service account or its password is wrong, or it isn't in
  `ollama_api_group`. pourOver says so in its reply instead of queueing.
- **Deletes** only ever touch the sender's own tasks, and only after a "yes".
