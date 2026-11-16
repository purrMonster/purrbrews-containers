# Radicale

Standalone CalDAV calendars and CardDAV contacts on percolator, at
`https://radicale.${DOMAIN}`. Basic authentication checks LLDAP directly;
Authelia ForwardAuth would break DAV clients. This is independent of OpenCloud.

## Bring up

1. In LLDAP's Users/Groups UI create `scottishfold`, Radicale's read-only bind
   account (the fleet's bots have cat names), set a password, and add it only to
   `lldap_strict_readonly`. Do not use the directory admin account.
2. Confirm each intended user, including admins, belongs to
   `${LLDAP_HOUSEHOLD_GROUP}`. `lldap-bootstrap.sh` adds the users it processes to
   both configured groups; it does not prove every existing admin is a member.
3. From `stacks/percolator`: `./setup-secrets.sh` (paste the reader password),
   `./render-configs.sh`, then `./compose.sh radicale up -d`.
4. Follow the runbook's Cloudflare and Pi-hole owner steps, then sign in at the
   URL and create a calendar and an address book.
5. iPhone: Settings → Calendar/Contacts → Add Account → Other →
   Add CalDAV Account / Add CardDAV Account. On iOS versions with app settings
   grouped together, start at Settings → Apps → Calendar or Contacts.
   Server: `radicale.${DOMAIN}`; username and password: the LLDAP account.
   Use SSL and port 443. Add both account types separately.

## Is it working?

- [ ] `./compose.sh radicale ps` shows healthy; logs have no LDAP bind errors.
- [ ] An unauthenticated `curl -I https://radicale.${DOMAIN}/` redirects to
      `/.web`; both `/.well-known/caldav` and `/.well-known/carddav` redirect to `/`.
- [ ] A household user's `curl -u <username> -X PROPFIND -H 'Depth: 0'
      https://radicale.${DOMAIN}/<username>/` prompts for the password and returns
      207; a wrong password or non-household account is refused.
- [ ] Two users cannot read or write each other's collections (`owner_only`).
- [ ] Calendar events and contacts created on the iPhone appear in Radicale;
      changes sync both ways over mobile data, away from home.
- [ ] Gatus is green. The owner has tested CrowdSec's actual DAV failure path
      or accepted the documented gap before public exposure.
- [ ] Back up with `sudo ./backup.sh nightly` and restore a collection to an
      isolated instance. Check event/contact contents, not only file presence.

## Gotchas

- A changed SSO/LLDAP password breaks phone sync until it is re-entered in both
  DAV accounts. These clients do not use browser SSO or its second factor.
- The image normally drops to 2999:2999. Here its entrypoint supports an
  explicit non-root `PUID:PGID`; data and the private rendered password belong
  to that same ops user. Do not make the password world-readable. Configparser
  reads the password from a file, avoiding INI interpolation of pasted secrets.
- LDAP travels over the private `proxy` Docker network; public DAV uses HTTPS.
  Failed-auth delay remains the upstream one-second default. Reader-password
  rotation needs setup/render and `up -d --force-recreate`.
- Root GET is a public web redirect, not proof that LDAP works. Gatus checks
  transport; the credential, isolation and sync checks above remain required.
- The stock CrowdSec generic 401 scenario filters POST. That does not prove
  protection against repeated DAV PROPFIND/GET failures; see the runbook.

Checked 2026-10-12: [image Dockerfile](https://github.com/tomsquest/docker-radicale/blob/3.8.3.0/Dockerfile)
pins Radicale 3.8.3 and installs `ldap3` and `curl`; its
[entrypoint](https://github.com/tomsquest/docker-radicale/blob/3.8.3.0/docker-entrypoint.sh)
supports non-root execution. [Radicale auth documentation](https://radicale.org/v3.html#auth)
and tagged `radicale/app/__init__.py` / `get.py` establish the option names and
DAV/root redirects. No Traefik DAV redirect middleware is needed.
