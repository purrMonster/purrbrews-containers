# FreshRSS

News and blog feed reader, with apps via the Google Reader / Fever APIs.

| | |
|---|---|
| Image | `freshrss/freshrss:1.30.0` (Debian; OIDC needs it) |
| URL | `https://freshrss.${DOMAIN}` |
| Data | `/srv/data/freshrss/data` (SQLite, config), `/srv/data/freshrss/extensions` |
| Secrets | `FRESHRSS_OIDC_CLIENT_SECRET`, `FRESHRSS_OIDC_CRYPTO_KEY` |

Feeds refresh at minutes 5, 25 and 45 of every hour (`CRON_MIN`).

## First run — order matters

With OIDC on, FreshRSS signs you in as the Authelia `preferred_username`. If no
FreshRSS admin has that name, there is no admin.

1. `./compose.sh freshrss up -d`, then open `https://freshrss.${DOMAIN}`. Authelia
   signs you in first, then the setup wizard runs.
2. Database: **SQLite**.
3. Authentication method: **HTTP**.
4. Admin username: **exactly your LLDAP username** (`barista`).
5. Finish.

## Is it working?

- [ ] Opening the site goes through Authelia and lands in FreshRSS as `barista`, with
      *Administration* in the settings menu.
- [ ] A feed added now shows new articles after the next refresh.
- [ ] `sudo docker exec freshrss cat /var/www/FreshRSS/data/users/_/log.txt` has no
      refresh errors.

## Gotchas

- **Every household member needs a FreshRSS user with the same name** as their LLDAP
  user, created by the admin (*Administration → Manage users*).
- **Mobile apps** use an API password set per user in *Profile → API management*;
  they don't go through Authelia.
- **The redirect URI includes `:443`** because FreshRSS always sends the port; that is
  what Authelia's client config expects.
