# Traefik → Ollama (native, on roastery)

```
LAN client → roastery:443 (Traefik) → ForwardAuth to Authelia on percolator:9091 → 127.0.0.1:11434 (Ollama)
```

Ollama has no authentication, so it listens on localhost only and this is the one
way in: a LAN address **and** an Authelia login. `ollama.${DOMAIN}` is in Authelia's
admin host list; dedicated LLDAP service accounts in `ollama_api_group` get
password-only (`one_factor`) access for API calls. There is deliberately no
unauthenticated route. If Authelia is down, it fails closed.

Traefik runs as a plain Windows process (`traefik.exe`), not in Docker Desktop, so it
can reach Ollama on localhost.

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
4. **Ollama on localhost.** As the Windows user who runs it:
   ```powershell
   [Environment]::SetEnvironmentVariable('OLLAMA_HOST', '127.0.0.1:11434', 'User')
   ```
   Quit Ollama from the tray, reopen it, and check
   `Get-NetTCPConnection -LocalPort 11434 -State Listen` shows `127.0.0.1`.
5. **Windows Firewall.** Allow inbound TCP 443 (and 80, for the redirect) to
   `traefik.exe` from the LAN. 11434 needs no rule.
6. **percolator.** Add roastery's IP to `FORWARD_AUTH_CLIENTS` in its `.env.local`,
   then `sudo ./firewall.sh` and `./compose.sh authelia up -d --force-recreate`
   there. The ForwardAuth call has to go straight to `:9091`; through percolator's
   Traefik, `X-Forwarded-Method` gets dropped.
7. **DNS.** roastery isn't in `NODE_IPS`, so add its fixed IP to
   `PIHOLE_DNS_EXTRA_HOSTS` on both sieve and mochaPot (`192.168.0.20 roastery`,
   semicolon-separated from anything already there), then `./render-configs.sh` and
   `./compose.sh pihole up -d` on each.
8. **Run it:** `.\traefik\start.ps1`. It stays in the foreground; no service or
   scheduled task is installed, so roastery has to be awake, logged in, with Ollama
   running.

After a template changes: pull, `.\render-configs.ps1`. Traefik watches the dynamic
directory; restart it for static config or token changes.

## Is it working?

1. On roastery, `curl.exe http://127.0.0.1:11434/api/tags` returns JSON.
2. From another machine, `roastery:11434` doesn't connect.
3. Without a session, `https://ollama.${DOMAIN}/api/tags` redirects to Authelia or
   returns an auth error, never model JSON.
4. Signed in as an admin, the same URL returns the JSON. A household-only account is
   refused.
5. With Authelia stopped, it fails closed.

## Known gap

ForwardAuth isn't an API key. The Ollama CLI and Open WebUI's backend can't do the
browser login, so grinder's Open WebUI can't reach Ollama through this, and pointing
it at the HTTPS URL doesn't change that. Machine-to-machine access needs its own
design that keeps Authelia in front; there's intentionally no bypass.

Reference: <https://www.authelia.com/integration/proxies/traefik/>
