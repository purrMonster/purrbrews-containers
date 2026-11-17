# Homepage

The household's start page: a tile for every app in the fleet.

| | |
|---|---|
| Image | `ghcr.io/gethomepage/homepage:v2.3.0` |
| URL | `https://homepage.${DOMAIN}` |
| Auth | Authelia ForwardAuth, admins + household |
| Data | none. Settings are tracked in `homepage/dashboard/` |
| Secrets | none |

## Design choices

- **No Docker socket.** Tiles are listed by hand in `dashboard/services.yaml`, not
  discovered from container labels. The socket would give a web app root on the node.
- **No API widgets.** Status widgets need an API key per app, and Homepage would
  then hold credentials for every service. Gatus on sieve is where health lives.
- **Settings are read-only mounts.** `{{HOMEPAGE_VAR_DOMAIN}}` is substituted by
  Homepage itself, so there is no template to render and nothing to go stale.
- **Behind Authelia, not public.** Homepage has no login of its own, and the tile list
  maps the network. Never route it through the tunnel.

## Bring up

```bash
./compose.sh homepage up -d
```

## Is it working?

- [ ] `https://homepage.${DOMAIN}` sends you to Authelia, then shows the tiles.
- [ ] Every tile opens its app (admin tiles need `purrbrews_admins`).
- [ ] `sudo docker logs homepage` has no `Host validation failed` or YAML errors.

## Changing it

Edit `dashboard/*.yaml`, commit, pull on the node. Homepage re-reads its files on
page load; no restart is needed. When an app is added anywhere in the fleet, add its
tile in the same commit.

## Gotchas

- **`HOMEPAGE_ALLOWED_HOSTS`** must list every name Homepage is served on. A request
  for any other host gets an error page.
- **A YAML error blanks the page.** Check `sudo docker logs homepage`.
