# Mealie

Recipe manager, meal planner and shopping list.

| | |
|---|---|
| Image | `ghcr.io/mealie-recipes/mealie:v3.26.0` |
| URL | `https://mealie.${DOMAIN}` |
| Data | `/srv/data/mealie` (SQLite, images, backups) |
| Secrets | `MEALIE_OIDC_CLIENT_SECRET` |

## Sign-in

*Login with Authelia* creates the Mealie account on first sign-in.

- **`purrbrews_household`** members get a normal account.
- **`purrbrews_admins`** members become Mealie admins.
- **Everyone must be in `purrbrews_household`**, admins included; Mealie refuses
  anyone outside `OIDC_USER_GROUP`. `lldap-bootstrap.sh` adds both groups.

## Bring up

```bash
./compose.sh mealie up -d
```

## First run

1. Sign in with Authelia as `barista`.
2. The image also ships a local account `changeme@example.com` / `MyPassword`. Sign
   in with it once and **delete it** (*Admin → Users*), or change its password.
3. *Admin → Site Settings*: every check green, including *Server Side Base URL*.

## Is it working?

- [ ] *Login with Authelia* works; `barista` has the admin menu.
- [ ] Importing a recipe from a URL works (outbound internet from the container).
- [ ] *Admin → Site Settings* shows no red items.

## Gotchas

- **`invalid_client` at sign-in** means the secret or its hash is wrong. Check with the
  `curl` test in `../authelia/README.md` before anything else.
- **SQLite must stay on local disk.**
