# Paperless-ngx

Scanned and emailed documents: OCR, tags, full-text search.

| | |
|---|---|
| Images | `ghcr.io/paperless-ngx/paperless-ngx:3.1.3`, `postgres:18`, `valkey/valkey:9.1.2-alpine` (task broker, required) |
| URL | `https://paperless.${DOMAIN}` |
| Data | `/srv/data/paperless/{data,media,export,consume}`, `/srv/data/paperless/{postgres,valkey}` |
| Secrets | `PAPERLESS_ADMIN_PASSWORD`, `PAPERLESS_SECRET_KEY`, `PAPERLESS_DB_PASSWORD`, `PAPERLESS_OIDC_CLIENT_SECRET` |

## Bring up

```bash
./compose.sh paperless up -d
./compose.sh paperless logs -f paperless     # first start runs migrations
```

## First run

1. Sign in at `https://paperless.${DOMAIN}` with *Authelia*. The account is created
   on first sign-in.
2. Make that account a superuser: sign out, sign in on the same page with the
   username/password form as `admin` / `PAPERLESS_ADMIN_PASSWORD`, then
   *Settings → Users & Groups* → edit the new user → *Superuser*.
3. Drop a PDF into `/srv/data/paperless/consume/` (writable by `barista`) or upload
   through the web page.

## Is it working?

- [ ] *Sign in with Authelia* completes and lands on the dashboard.
- [ ] A dropped PDF appears within a minute with searchable text.
- [ ] `./compose.sh paperless logs paperless` shows the consumer and scheduler
      running, no Redis or database errors.

## Gotchas

- **`admin` is the break-glass account** if Authelia is down. Keep its password in
  Vaultwarden.
- **OCR languages:** `PAPERLESS_OCR_LANGUAGE` in `.env.local` (e.g. `eng+hin`).
  Languages outside the image's bundled set also need `PAPERLESS_OCR_LANGUAGES`.
- **Office documents** (Word, email attachments) need Tika and Gotenberg, which
  aren't in this stack. PDFs and images work.
- **Postgres 18 stores data under `postgres/18/docker`**; the whole
  `/var/lib/postgresql` is mounted, not `.../data`.
- **Back up with the exporter** as well as the database:
  `sudo docker exec paperless document_exporter ../export` writes to
  `/srv/data/paperless/export`.
