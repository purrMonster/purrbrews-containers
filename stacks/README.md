# stacks

One directory per node, one directory per app inside it:

```
stacks/<node>/
├── README.md              role, app list, bring-up order, day-2
├── local.env.example      node settings template → .env.local (gitignored)
├── setup-secrets.sh       .env.local + generate-secrets.sh + render-configs.sh
├── generate-secrets.sh    creates each app's secrets.env.local on the node
├── render-configs.sh      renders */config/*.template
├── compose.sh             docker compose wrapper (env files, preflight, --all)
└── <app>/
    ├── README.md          what it is, first run, "is it working?" checklist
    ├── docker-compose.yml
    ├── data-dirs          directories compose.sh creates before `up` (optional)
    ├── prepare.sh         hook compose.sh runs before `up` (optional)
    └── config/*.template  rendered next to themselves (optional)
```

[`percolator/`](percolator/) is the reference implementation of this layout.

| Node | Role | Stack |
|---|---|---|
| `sieve` | Network: DNS, DHCP, tunnel, alerting | [`sieve/`](sieve/README.md) |
| `percolator` | Identity (SSO) and daily apps | [`percolator/`](percolator/README.md) |
| `cellar` | Storage/ops: backups, file shares, monitoring | [`cellar/`](cellar/README.md) |
| `mochaPot` | Home automation, media, kiosk display | [`mochaPot/`](mochaPot/README.md) |
| `grinder` | AI/automation: n8n, embeddings, tracking apps | [`grinder/`](grinder/README.md) |

## Ingress: a Traefik on every node

Each node runs its own Traefik for its own apps only, so a broken proxy or a dead
node takes down only that node's pages. Login stays one SSO, from Authelia on
percolator.

- **Routes** can be compose labels, a rendered `traefik/config/*.template` or a
  `traefik/dynamic/*.yml` Go template (sieve's style, no socket, no render step).
  Keep every `Host(...)` rule on one line in one of those forms: sieve's
  `setup-secrets.sh` turns each into a Pi-hole record for its node. Re-run it on
  sieve, and recreate Pi-hole, after adding a route.
- **Certificates:** Cloudflare DNS-01. No two nodes may request the same set
  (percolator holds the `*.${DOMAIN}` wildcard; other nodes use per-name
  certificates), or they share Let's Encrypt's five-a-week limit.
- **SSO from another node:** a ForwardAuth middleware on an HTTPS router calling
  Authelia **directly** on `http://192.168.0.11:9091/api/authz/forward-auth`, never
  through percolator's Traefik, which drops `X-Forwarded-Method`.
  - Add the node's IP to percolator's `FORWARD_AUTH_CLIENTS`.
  - Add its admin hosts to Authelia's admin-only rule.
- **Dashboard** at `traefik-<node>.${DOMAIN}` on nodes other than percolator.

## Conventions

- **Pin image tags** and write the date they were checked in a comment. `:latest`
  only with a written reason.
- **Data outside the repo.** Bind mounts use `${DATA_DIR}/<app>/…` (from
  `/opt/purrbrews/.env`). List every directory in `<app>/data-dirs` with the owner
  the image needs (`PUID`/`PGID` mean the ops user), so Docker never creates it as
  root and crash-loops a non-root image.
- **Secrets are generated on the node.** Reference `${VARS}` from the app's
  `secrets.env.local`; add the key to the node's `generate-secrets.sh`. Random
  values are hex. Values containing `$` are written single-quoted.
- **Config templates.** Files needing substitution are `config/*.template`.
  `render-configs.sh` refuses a template with an unset variable, and `compose.sh`
  refuses to start an app whose rendered file is missing or older than its inputs.
  A template whose rendered file must be world-readable starts with
  `# render-mode: 0644` and must not contain secrets.
- **One web network per node.** Traefik and each app's web container join the
  external `proxy` network; databases stay on the app's own project network.
- **Publish as little as possible.** Route through Traefik instead of publishing a
  port; bind admin-only ports to `127.0.0.1`. Check `ss -tlnp` before adding one and
  add any UFW rule to the node's `firewall.sh`, never by hand.
- **Check auth defaults first.** Note in the app README whether the image ships a
  default account and how first login works.
- **Test, don't just parse.** `docker compose config` proves syntax; bring the app
  up and confirm its README checklist before calling it done.

## Adding a node

Copy the scripts from `percolator/` (they contain nothing node-specific except the
`APPS` order in `compose.sh` and the per-app section of `generate-secrets.sh`), write
`local.env.example`, `firewall.sh` and a `README.md`, then add apps one at a time.
Give the node its own `traefik/` (see *Ingress* above), and add its checks to Gatus
on sieve.
