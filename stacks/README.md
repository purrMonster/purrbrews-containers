# stacks

One directory per node, one directory per app inside it:

```
stacks/<node>/<app>/docker-compose.yml
```

## Conventions

- **Pin image tags.** Record the date the tag was checked in a comment; `:latest`
  only with a written reason (e.g. a CVE-heavy app where staying current wins).
- **Data outside the repo.** Bind mounts point at `/srv/data/<app>/…`
  (`DATA_DIR`) or `/srv/media` (`MEDIA_DIR`). Note any required
  `mkdir` + `chown` (e.g. uid 1000 images) in the node README.
- **Secrets are generated on the node.** Reference `${VARS}` from the app's
  `secrets.env.local`; add the key to that node's `generate-secrets.sh`.
- **Config templates.** Files needing substitution are committed as
  `*.template` and rendered by `render-configs.sh`; add the rendered filename
  to `.gitignore`.
- **Check before you publish a port.** Run `ss -tlnp` on the host; watch for
  `network_mode: host` apps on the same node.
- **Check auth defaults first.** Note in the node README whether the image ships
  a default account and how first login works.
- **Test, don't just parse.** `docker compose config` proves syntax; bring the
  app up and inspect what it produced before calling it done.

## Adding a node

Create `stacks/<node>/` with `compose.sh`, `render-configs.sh`,
`setup-secrets.sh`, `generate-secrets.sh`, `local.env.example` and a
`README.md` listing each app's bring-up steps.
