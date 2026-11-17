# Image updates, November 2026: what changed and what's new

Every pinned image was moved to its newest **stable** release on 2026-11-17,
while every app still starts empty (runbook, 2026-11-17). This page covers,
for each app, what the release notes between the old and new pin say:

- **Acted on:** the breaking changes that touch this repo, and what was done about them.
- **New:** features worth knowing about.

Sources are each project's GitHub releases between the two pins, plus the
upgrade docs where a release pointed to them. These were read on 2026-11-17;
nothing has run on a node yet.

## Two majors

### n8n: 2.42.6 → 2.48.4, and why not 3.x

- **No stable 3.x yet.** n8n 3.0 came out on 2026-10-27 as a beta. Every 3.x
  tag, and 2.49.0 too, is a pre-release on GitHub, and the stable 3.x is
  planned for early December. 2.48.4 is the newest stable release.
  - The first image update on this branch had picked 2.49.0, which is a beta.
    That is now corrected to 2.48.4.
- **3.0 makes no feature jump.** It removes legacy nodes and tightens
  defaults, and the move is one-way: there is no going back to 2.x. Since n8n
  starts empty here, the move costs nothing once 3.x is stable.
- **Changes in 3.0 that matter here:**
  - **Tailscale addresses blocked.** The default SSRF block list gains
    `100.64.0.0/10`. A workflow calling a tailnet address then needs it in
    `N8N_SSRF_ALLOWED_IP_RANGES`.
  - **Shorter Code node limit.** The task runner timeout drops from 5 minutes
    to 1 (`N8N_RUNNERS_TASK_TIMEOUT`).
  - **Storage folder renamed.** `~/.n8n/binaryData` becomes `~/.n8n/storage`.
  - **Community nodes.** Unverified community nodes are off by default.
  - **Docker only.** Self-hosted n8n requires Docker, which is already how it
    runs here.
- **New in 2.43–2.48:**
  - Browser Use available to everyone.
  - Google Vertex AI credentials.
  - Monday.com node v2.
  - Prompt caching in the Anthropic node.
  - Custom SSL certificates for Postgres credentials.
  - A **Migration Report** (Settings → Migration Report) that lists what 3.0 would break.

### OpenCloud: 7.2.4 → 9.1.1

- **Production line, not rolling.** OpenCloud publishes two channels. 9.2.0
  is a *rolling* release, which upstream says is not for production. The
  production line is 9.1.x on the same `opencloudeu/opencloud` image, so the
  pin is 9.1.1.
- **Acted on:**
  - `THUMBNAILS_TRANSFER_TOKEN` is ignored from 9.x (thumbnails moved into the
    webdav service), so it was removed from the compose file and from
    `secrets.conf`.
  - The 8.x search reindex and the 9.x `opencloud init --diff` config patch
    only apply to existing installs. A fresh 9.1 install writes its own config.
- **Not affected:**
  - Custom thumbnail settings, email templates, `GRAPH_SPACES_DEFAULT_QUOTA`
    and separate containers: none are used here.
- **To check on first bring-up:**
  - The custom CSP (`config/csp.yaml.template`) allows only `'self'` and
    Authelia. Check that the new in-browser apps (Excalidraw, Apollon) and
    previews still load under it.
- **New since 7.2:**
  - **9.0:**
    - **Guest access:** share with anyone by email, with no account needed.
      Off by default; it needs `OC_ENABLE_GUEST_LINKS=true` and SMTP.
    - Tags in search.
    - "Folders first" sorting.
    - Shares appear live, without a reload.
    - Search results show the matching text.
    - A redesigned app store that shows version compatibility.
    - Apollon UML diagrams.
    - HEIC/HEIF/AVIF previews, which need an extra imagor container.
  - **8.1:** Excalidraw whiteboards, a web UI that loads about 40% faster, and
    creating a space in one step.
  - **8.0:** syntax highlighting in the editor, and over 50 search fixes.
  - **7.5:** end-to-end encrypted vaults for folders and spaces, an EPUB
    reader, media controls and SVG files in the preview app, and filters in
    favourites.
  - **7.4:** an admin announcement banner.
  - **7.3:** a calmer web interface, editor improvements, and @-mentions in documents.

## Apps

| App | Old → new | Acted on / to know | New |
|---|---|---|---|
| Immich (server + ML) | v3.3.3 → v3.4.1 | 3.3.5 fixed a certificate-authority compromise and Node.js security issues. Its Postgres image is unchanged. | Built-in backups; JPEG XL as a target format and decoder in the mobile app; tags in the mobile app; smoother timeline scrubbing on mobile; workflow and performance improvements |
| Karakeep | 0.33.2 → 0.35.0 | Sign-in moved from next-auth to better-auth (automatic on upgrade; this install starts fresh). Meilisearch moves to v1.55.0, the version Karakeep's compose pins. | Redesigned web and mobile apps with a proper dark mode; smart lists built from tags, favourites and age; a highlights page; notes that save as you type; automatic offline downloads on mobile; a crawler that gets blocked less; cleaner reader view (Defuddle) |
| Mealie | v3.28.0 → v3.31.0 | 3.31.0 fixes a batch of security issues. Request bodies are capped by `MAX_UPLOAD_SIZE_MB` (default 1024). Password-reset links expire after 1 hour. The API no longer returns `cookTime`. | Metric/imperial conversion; structured recipe times and filtering by time; meal plan as an iCal feed; sign-in through a reverse proxy; custom name and logo; in-app AI prompt editing; per-step durations; whole-week meal plan entries; PDF export; a day view in the meal planner |
| Paperless-ngx | 3.3.0 → 3.5.0 | none | Manual workflow trigger; notes rendered as Markdown; custom fields in workflow title templates; relative-date custom-field queries; local 2FA skipped for trusted OIDC sign-ins; PDF thumbnails via poppler; an upload button in the navbar |
| Vaultwarden | 1.37.4 → 1.37.5 | Invalid config values now stop startup (numeric limits are stricter). None of the affected settings are set here. The bundled web vault is now v2026.10.1. | Unresponsive WebSocket connections are closed |
| Vikunja | 2.7.0 → 2.8.0 | 2.7.1 fixed 41 security issues and 2.8.0 fixes 19 more. | Trash bin with undo for tasks and projects; link an SSO account to a local one |
| Radicale | 3.8.3.0 → 3.9.1.1 | **Security:** 3.9.1 fixes LDAP sign-in for servers that accept an unauthenticated named bind. This repo uses LDAP auth, so the update matters. | Zstd-compressed responses; a property-locking permission (`l`) |
| Actual Budget | 26.10.0 → 26.11.0 | none in the GitHub release | Release notes are on actualbudget.org/blog/release-26.11.0 (not read) |
| FreshRSS | 1.30.1 → 1.30.4 | Security fixes: `data:` URIs blocked, no DNS leak through a proxy, Fever API key no longer logged | Lower memory use on export |
| Homepage | v2.5.0 → v2.8.0 | none | Quicklaunch can be turned off; the sign-in page is translated; NetBird and more Beszel widget fields |
| FitTrackee | v1.3.5 → v1.3.8 | Sign-in tokens moved to a cookie with a shorter lifetime (1.3.6) | none |
| Traccar | 6.16 → 6.17 | No release notes on GitHub; the upgrade gate records the version on a fresh install | not read |
| Open WebUI | v0.12.0 → v0.13.4 | One setting removed (Show Files on Terminal Select) | Comment threads and a notification inbox; end-to-end encrypted direct chats; side chats (`/side`); notes with pages and live presence; workspace-wide search; much cheaper tool calls; analytics sessions; MCP apps in chat; much more for its Open Terminal add-on, which this fleet doesn't run |

## Home

| App | Old → new | Acted on / to know | New |
|---|---|---|---|
| Home Assistant | 2026.10.1 → 2026.11.2 | HACS is now built in as the **Marketplace**, and the separate HACS installer stops working. Read the release's "Backward-incompatible changes" before restoring any old config (this install starts fresh). | Exclude items from automation targets; copy/paste dashboard sections; sections that fill themselves; derive energy totals from a power sensor; "why did that happen" traces and per-integration live logs; remove bad readings from history; Matter cameras with two-way audio; backups to local drives; LoRaWAN; Zigbee Green Power (batteryless switches); naming that adds area and device context once |
| Music Assistant | 2.10.6 → 2.10.12 | none | Sendspin clients paired through Home Assistant; Sendspin line-ins as their own player; multiple Pocket Casts accounts |
| ESPHome | 2026.9.1 → 2026.10.2 | none in the GitHub notes (the full changelog is on esphome.io) | Device Builder offers host builds as a download |

## Network, monitoring and fleet

| App | Old → new | Acted on / to know | New |
|---|---|---|---|
| Pi-hole (both) | 2026.09.0 → 2026.11.0 | **Security:** 17 advisories fixed across FTL, Web and Core, including a stored XSS, file reads, local privilege escalation and DHCP use-after-free | none beyond the fixes |
| Traefik | v3.7.14 → v3.7.19 | Patch releases only | none |
| CrowdSec | v1.8.1 → v1.8.2 | none | WAF rate limiting; bot detection (`cscli bot`); faster regex processing |
| cloudflared | 2026.10.0 → 2026.11.1 | none listed | none listed |
| NetAlertX | 26.10.0 → 26.10.28 | On *existing* installs `NMAPDEV_ARGS` needs `--privileged`; this repo doesn't set it. The old API endpoints are being phased out. | A Sources tab; a session info tab; a pending-updates indicator |
| Gatus | v5.37.0 → v5.38.0 | none | Resend alerting; SSH keyboard-interactive auth; maintenance windows for DNS/SSH endpoints |
| ntfy | v2.29.0 → v2.38.1 | Message database schema changes (downgrades need manual SQL). Daily limits now live in the user database. An invalid config now fails at startup. | Attachment links in email; SMTP LOGIN auth; `/v1/ready`; `Retry-After` and RateLimit headers; experimental PostgreSQL clustering |
| Scrutiny (hub + collector) | v0.9.5 → v0.10.0 | Device names (`friendly_name`) now live in the database and are set from the device page; this repo never set them in config | Alerts when a device misses its upload; total bytes read/written; per-device notification settings; InfluxDB 2.8 in the omnibus image |
| Komodo (core + periphery) | 2.3.3 → 2.3.4 | Patch release | none |
| Speedtest Tracker | v1.15.0 → v1.15.1 | Patch release | none |
| Postfix relay | 5.1.0 → 5.2.1 | none | none listed |

## Databases and bases

All stay on their major version: Postgres 16.15 → 16.16 and 18.6 → 18.7,
PostGIS 16-3.5 → 16-3.7, Mongo 7.0.43 → 7.0.48, Redis and Valkey patch
releases, and pgvector unchanged. The embedding worker's base image moves to
`python:3.14.10-slim`. Meilisearch goes to v1.55.0, as Karakeep pins it;
v1.57.0 exists but Karakeep isn't tested with it.
