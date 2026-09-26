# Home Assistant

`https://homeassistant.${DOMAIN}`, or `http://192.168.0.13:8123` directly.

Host networking (discovery needs it), with its own Postgres for the recorder on
`127.0.0.1:5432`. The onboarding wizard runs on the first visit; there's no
default account.

## configuration.yaml

Three things can't be set from compose and live in
`/srv/data/homeassistant/configuration.yaml`. Restart after changing it.

**Trust Traefik.** Without this every proxied request is rejected as coming from
an untrusted proxy. Trust the whole `mochapot_net` subnet (`PROXY_SUBNET` in
`.env.local`), not Traefik's container IP: that changes whenever it's recreated,
and I spent an evening on 400s learning so.

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.30.13.0/24   # PROXY_SUBNET
```

**Recorder on Postgres, and trimmed before the sensors arrive.** ESPHome publishes
diagnostic entities that update constantly and nobody reads.

```yaml
recorder:
  db_url: postgresql://homeassistant:<HA_DB_PASSWORD>@127.0.0.1:5432/homeassistant
  purge_keep_days: 14
  exclude:
    domains: [automation, updater]
    entity_globs: ["sensor.*_uptime", "sensor.*_linkquality"]
```

`HA_DB_PASSWORD` is in `homeassistant/secrets.env.local`. Until this is done HA
stays on SQLite, which works fine, just slower.

**Sign in with Authelia** ([hass-oidc-auth](https://github.com/christiaangoossens/hass-oidc-auth), from HACS):

1. Install HACS, then *OpenID Connect for Home Assistant* from it.
2. The client secret is generated on percolator, where Authelia is:
   `grep '^HOMEASSISTANT_OIDC_CLIENT_SECRET=' /opt/purrbrews/stacks/percolator/authelia/secrets.env.local`
3. Put it in `/srv/data/homeassistant/secrets.yaml` as `oidc_client_secret`, and add:
   ```yaml
   auth_oidc:
     client_id: "homeassistant"
     client_secret: !secret oidc_client_secret
     discovery_url: "https://authelia.<DOMAIN>/.well-known/openid-configuration"
     claims:
       username: "preferred_username"
       display_name: "name"
       groups: "groups"
     groups_scope: "groups"
   ```
4. Keep the default `homeassistant` provider in `http.auth_providers` too. That's
   the local login, and the way in when Authelia is down.

There's deliberately no ForwardAuth in front of it (same as Nextcloud and
Paperless): the app's own OIDC is the gate, so its login page is reachable
without a session.

## Is it working?

- the onboarding page, then the dashboard, loads at `https://homeassistant.${DOMAIN}`
- *Log in with Authelia* appears on the login page and works
- Settings → System → Logs has no `untrusted proxy` errors

## Gotcha

Docker copies the host's `/etc/resolv.conf` into a container once, when it's
created. This one was created while mochaPot was still on bootstrap DNS, and kept
asking public DNS for `authelia.${DOMAIN}` ("Name does not resolve") long after the
host had moved to Pi-hole. The compose file now sets `dns:` explicitly, but the
rule stands for every host-networked container: when a node's DNS changes,
`./compose.sh <app> up -d --force-recreate`. A restart keeps the old copy.
