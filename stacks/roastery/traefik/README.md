# Traefik on roastery (native): llama-swap and meowGram

```
LAN client → roastery:443 (Traefik) → ForwardAuth to Authelia on percolator:9091 → 127.0.0.1:9292 (llama-swap)
```

llama-swap (the local LLMs, [`../llama-swap`](../llama-swap/README.md)) has no
authentication, so it publishes on localhost only and this is the one way in: a
LAN address **and** an Authelia login. Its hostname is still
`ollama.${DOMAIN}`, from before Ollama was replaced (2026-10-07): Authelia's
rules, the Pi-hole records, the tunnel config and the tests know it by that
name. `ollama.${DOMAIN}` is in Authelia's admin host list; dedicated LLDAP
service accounts in `ollama_api_group` get password-only (`one_factor`) access
for API calls. There is deliberately no unauthenticated route. If Authelia is
down, it fails closed.

The same Traefik serves meowGram (`meow.${DOMAIN}`, [`../meowgram`](../meowgram/README.md)),
which signs in with Authelia OIDC itself instead of ForwardAuth.

Traefik runs as a plain Windows process (`traefik.exe`), not in Docker Desktop.
It reaches llama-swap and meowGram on the ports Docker Desktop publishes on
`127.0.0.1`.

## Setting it up

1. **Traefik itself.** Download the Windows amd64 Traefik v3 binary from
   [the releases page](https://github.com/traefik/traefik/releases), check its
   published checksum, and put it here as `traefik.exe` (gitignored).
2. **Settings.** `DOMAIN` and `TRAEFIK_ACME_EMAIL` in `stacks/roastery/.env.local`;
   `LAN_CIDR` and `PERCOLATOR_LAN_IP` come from `stacks/fleet.env`. Then render:
   ```powershell
   cd stacks\roastery
   .\setup-secrets.ps1
   ```
3. **The Cloudflare token.** Copy `secrets.env.example` to `secrets.env.local` here
   and fill in `CF_DNS_API_TOKEN` (same token and permissions as the other nodes),
   or point `CF_DNS_API_TOKEN_FILE` at a file outside the repo. `start.ps1` parses it
   as plain `KEY=value` lines: no expansion, nothing executed.
4. **llama-swap running**, on `127.0.0.1:9292` ([its README](../llama-swap/README.md)).
5. **Windows Firewall.** Allow inbound TCP 443 (and 80, for the redirect) to
   `traefik.exe` from the LAN. 9292 needs no rule: it's bound to loopback.
6. **percolator.** roastery's IP in `FORWARD_AUTH_CLIENTS` in its `.env.local`,
   then `sudo ./firewall.sh` and `./compose.sh authelia up -d --force-recreate`
   there. The ForwardAuth call has to go straight to `:9091`; through percolator's
   Traefik, `X-Forwarded-Method` gets dropped. percolator keeps this across a
   roastery rebuild; check it's still there if roastery's IP changed.
7. **DNS.** roastery isn't in `NODE_IPS`, so its fixed IP goes in
   `PIHOLE_DNS_EXTRA_HOSTS` on both sieve and mochaPot (`192.168.0.20 roastery`,
   semicolon-separated from anything already there), then `./render-configs.sh` and
   `./compose.sh pihole up -d` on each. Also kept across a roastery rebuild.
8. **Run it:** `.\traefik\start.ps1`. It stays in the foreground. Before the
   2026-10-07 wipe it ran as a `traefik` scheduled task at boot, made by hand
   and not in this repo, so it went with the wipe. Recreate it the same way, and
   untick *Stop the task if it runs longer than*, or Windows kills it after 3
   days (runbook, 2026-10-04).

After a template changes: pull, `.\render-configs.ps1`. Traefik watches the dynamic
directory; restart it for static config or token changes.

**A leftover `config\dynamic\ollama.yml`** (rendered before 2026-10-07, gitignored)
must be deleted: Traefik loads every file in that folder, and its `authelia`
middleware would clash with the new route's.

## Is it working?

1. On roastery, `curl.exe http://127.0.0.1:9292/health` answers `OK`.
2. From another machine, `roastery:9292` doesn't connect.
3. Without a session, `https://ollama.${DOMAIN}/v1/models` redirects to Authelia or
   returns an auth error, never the model list.
4. Signed in as an admin, the same URL lists `assistant` and `fast`. A
   household-only account is refused.
5. With Authelia stopped, it fails closed.

## Known gap

ForwardAuth isn't an API key. Open WebUI's backend can't do the browser login, so
grinder's Open WebUI can't reach llama-swap through this, and pointing it at the
HTTPS URL doesn't change that. Machine-to-machine access needs its own design;
the options are in the runbook (2026-10-07), and none is chosen yet. There's
intentionally no bypass in the meantime.

Reference: <https://www.authelia.com/integration/proxies/traefik/>
