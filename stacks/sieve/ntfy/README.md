# ntfy

Push notifications for the household's phones: fleet alerts now, and anything else
later (backups, automations). Image `binwiederhier/ntfy:v2.28.0`.

One address everywhere, `https://ntfy.${DOMAIN}`:

- **Away from home:** through the Cloudflare tunnel, straight to the container.
- **At home:** Pi-hole resolves the name to sieve, and sieve's Traefik serves it.
  Alerts still reach phones on Wi-Fi when the internet link is down.

ntfy has its own accounts, so there is no Authelia in front of it on either path.

## Accounts and access

Anonymous access is **denied**, sign-up is off, and every account is declared in the
compose file from `ntfy/secrets.env.local` and applied on each start.

| Account | Role | Access | Used by |
|---|---|---|---|
| `barista` (`NTFY_ADMIN_USER`) | admin | everything | your phones and browser |
| `gatus` | user | write-only to `purrbrews-alerts`, by token | Gatus |

`generate-secrets.sh` creates the passwords and Gatus's token, and bcrypt-hashes the
passwords with ntfy's own hasher (`sudo docker run … ntfy user hash`). Only the hashes
reach ntfy.

Tested before first deploy: Gatus's token can publish to the topic but can't read it;
anonymous publishing gets `403`; the admin can read.

## Phone setup

1. Install the **ntfy** app (Android: Play Store or F-Droid; iOS: App Store).
2. Settings → **Manage users** → add server `https://ntfy.${DOMAIN}`, user `barista`,
   and the password from `NTFY_ADMIN_PASSWORD` (`grep NTFY_ADMIN ntfy/secrets.env.local`).
3. Subscribe to `purrbrews-alerts` on `ntfy.${DOMAIN}`.
4. Also subscribe to the **critical topic on ntfy.sh**: server `https://ntfy.sh`,
   topic = `NTFY_CRITICAL_TOPIC` from `gatus/secrets.env.local`. This is where alerts
   go when the self-hosted server is the thing that's broken.
5. Android: exempt the app from battery optimisation, or alerts arrive late.

Test from sieve:

```bash
source <(grep -E '^(GATUS_NTFY_TOKEN|NTFY_ALERT_TOPIC)=' gatus/secrets.env.local)
sudo docker run --rm --network sieve_edge curlimages/curl -s \
  -H "Authorization: Bearer ${GATUS_NTFY_TOKEN}" -H "Title: test" \
  -d "hello from sieve" "http://ntfy:8080/${NTFY_ALERT_TOPIC}"
```

## Adding someone

Accounts are declarative, so a user is added through config, not `ntfy user add`.
Put your additions in the `NTFY_EXTRA_*` lines of `ntfy/secrets.env.local`. That
script keeps them and appends them to what ntfy reads; the `NTFY_AUTH_*` lines are
rebuilt on every run.

```bash
sudo docker run --rm -it binwiederhier/ntfy:v2.28.0 user hash    # bcrypt for their password
sudo docker run --rm binwiederhier/ntfy:v2.28.0 token generate   # only if it's a service needing a token
```

```ini
NTFY_EXTRA_USERS='partner:$2a$10$…:user,netalertx:$2a$10$…:user'
NTFY_EXTRA_ACCESS='partner:purrbrews-alerts:ro,netalertx:netalertx:wo'
NTFY_EXTRA_TOKENS='netalertx:tk_…:netalertx'
```

Then run `./generate-secrets.sh && ./compose.sh ntfy up -d`.

**Removing someone from the config deletes the account** on the next start.

To change the `barista` password, set a new `NTFY_ADMIN_PASSWORD`, delete the
`NTFY_ADMIN_HASH` line and run the same two commands.

## Notes

- **Data:** `/srv/data/ntfy` (user database, 24 h message cache, attachments). Runs as
  `PUID:PGID`, read-only root filesystem.
- **iOS:** `NTFY_UPSTREAM_BASE_URL=https://ntfy.sh` is required for iOS push. Only a
  poll request passes through ntfy.sh; message contents stay here.
- **Public topics on ntfy.sh** are readable by anyone who knows the name. The critical
  topic is 24 random hex characters; treat it like a password.
