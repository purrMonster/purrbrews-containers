# Mail relay

The fleet's outgoing mail. Apps hand their mail to this Postfix, which sends it
on to Purelymail as `purrBrews@${DOMAIN}`: Authelia's password resets and 2FA
enrolment, Vaultwarden's invites and alerts, and whatever else is wired up later.

| | |
|---|---|
| Image | `boky/postfix:5.1.0-alpine` |
| Listens | `mail-relay:587` on the `proxy` network; `192.168.0.11:587` for `MAIL_RELAY_CLIENTS` |
| Upstream | `smtp.purelymail.com:587`, STARTTLS, certificate verified (`secure`) |
| Data | `/srv/data/mail-relay/spool` (the queue), `tls/` (root only), `tls-public/` (the CA clients trust) |
| Secrets | `MAIL_RELAY_PASSWORD`: a Purelymail **app password** of `purrBrews@${DOMAIN}` |

## Why a relay

- **Mail survives an outage.** If Purelymail or the internet is down, the
  message waits in the queue (on disk) and is retried for five days. An app
  talking to Purelymail directly would just fail the send.
- **One credential**, here, instead of a copy in every app.
- **One sender.** Every message leaves as `purrBrews@${DOMAIN}` whatever the
  app put in From; the display name is kept (`Authelia <purrBrews@...>`). Mail
  goes from the main domain because Purelymail signs (DKIM) only that, not
  subdomains.

## Who can send through it

| From | Allowed | How it's checked |
|---|---|---|
| Containers on percolator's `proxy` network | yes | `mynetworks`, then `smtpd_client_restrictions` |
| Fleet nodes in `MAIL_RELAY_CLIENTS` (`.env.local`) | yes | ufw `route` rule (`firewall`) and `mynetworks` |
| Anything else on the LAN | no | ufw drops it; Postfix would also refuse it ("Client host rejected") |
| A sender outside `${DOMAIN}` | no | `ALLOWED_SENDER_DOMAINS` |
| Plain text, no STARTTLS | no | `smtpd_tls_security_level: encrypt` ("530 Must issue a STARTTLS command first") |

The image's own default lets any client relay as long as the sender domain
matches; `smtpd_client_restrictions` is what makes the network list a real
gate (found in testing, 2026-10-08).

Clients connect without a password. The network is the credential, which is
why the list is short and the port is not published beyond it.

### TLS between the apps and the relay

`prepare.sh` makes a private CA and a ten-year certificate for `mail-relay` and
`192.168.0.11` on the first `up`. Clients check it:

| Client | Verifies the relay? | How |
|---|---|---|
| Authelia | yes | `certificates_directory` = `tls-public/` (holds `ca.crt`) |
| Vaultwarden | yes | `SSL_CERT_FILE` = `tls-public/bundle.crt` (the host's public roots + `ca.crt`, rebuilt on every `up`) |
| LLDAP | not wired | see below |
| Gatus on sieve | no (`insecure`) | it only checks the relay answers and offers STARTTLS |
| Another node's app | when given `ca.crt` | copy `tls-public/ca.crt` to that node; it's public |

**LLDAP has no mail, on purpose.** Its own "forgot password" link is the only
thing it would send, and Authelia already does password resets for every user
(writing the new password into LLDAP). LLDAP 0.6.3 also can't trust a private
CA: its TLS library has the public roots compiled in and ignores
`SSL_CERT_FILE` (tested: `UnknownIssuer`).

## First run

1. **Purelymail** (owner): create the user `purrBrews@${DOMAIN}`, turn on its
   two-factor, then create an **app password** for it. With 2FA on, the account
   password no longer works for SMTP; the app password is what goes here, and
   it can be revoked alone.
2. On percolator, from `/opt/purrbrews/stacks/percolator`:
   ```bash
   ./setup-secrets.sh                 # asks for MAIL_RELAY_PASSWORD: paste it
   ./compose.sh mail-relay up -d      # makes the certificates, starts the relay
   ```
3. Set `MAIL_RELAY_CLIENTS` in `.env.local` (example in `../local.env.example`),
   then `sudo ./firewall.sh`. Only needed for nodes other than percolator.
4. Recreate the apps that send through it, so they pick up the new config and
   the CA:
   ```bash
   ./render-configs.sh
   ./compose.sh authelia up -d --force-recreate
   ./compose.sh vaultwarden up -d --force-recreate
   ```

Order matters only the first time: the relay's `up` creates `tls-public/`,
which Authelia and Vaultwarden mount. `node.conf` lists it before them.

## Is it working?

- [ ] `docker ps` shows `mail-relay` as `healthy`.
- [ ] **Authelia**: *Reset password* on the login page for a user with a real
      email; the mail arrives from `Authelia <purrBrews@${DOMAIN}>`.
- [ ] **Vaultwarden**: `/admin` → *SMTP Email Settings* → *Send test email*.
- [ ] The relay's log shows `status=sent` for both:
      `docker logs mail-relay 2>&1 | grep status=`
- [ ] From a LAN laptop, `nc -vz 192.168.0.11 587` times out; from a node in
      `MAIL_RELAY_CLIENTS` it connects.
- [ ] Gatus on sieve shows *mail relay* green.

What a failure looks like in the log:

| Line | Meaning |
|---|---|
| `status=deferred (SASL authentication failed; ... 535 ...)` | wrong or revoked app password: see *Changing the app password* |
| `status=deferred (Server certificate not verified)` | upstream isn't really Purelymail (DNS, interception); nothing was sent and no password was offered |
| `status=deferred (connect to smtp.purelymail.com...)` | internet or Purelymail down; it retries by itself |
| `NOQUEUE: reject: ... Client host rejected` | a client outside the allowed networks |
| `NOQUEUE: reject: ... Recipient address rejected: Access denied; from=<...>` with a `from` outside `${DOMAIN}` | an app sending as some other domain |

## Changing the app password

```bash
./setup-secrets.sh                       # paste the new one
./compose.sh mail-relay up -d            # recreates the relay with it
docker exec mail-relay postqueue -f      # send what waited, now
```

Mail queued meanwhile stays queued: the spool is on disk, the config is not
(see Gotchas). Tested 2026-10-08: wrong password, mail deferred with `535`,
fixed, recreated, queued mail delivered.

## Gotchas

- **Authelia starts without the relay** (`disable_startup_check: true`), so
  logins keep working when mail doesn't. While the relay is down, a reset
  request fails at once with "Operation failed" and Authelia logs
  `Error occurred sending the identity verification email`. Mail is not
  queued for later in that case: only what reached the relay is.
- **The queue**: `docker exec mail-relay postqueue -p` lists it,
  `docker exec mail-relay postqueue -f` retries now, and
  `docker exec mail-relay postsuper -d ALL deferred` drops what's stuck (only
  after reading why it's stuck). A queue that keeps growing means Purelymail is
  refusing the mail; Gatus can't see that.
- **Purelymail's limits.** About 3000 messages a day to outside addresses, and
  its terms forbid bulk or marketing mail. Notifications only.
- **`/etc/postfix` is a tmpfs**, rebuilt from the environment on every start.
  The image declares it a volume, and Compose carries an anonymous volume over
  a recreate, so without it a changed password or a removed `POSTFIX_*` setting would
  stay in force (the image appends the new password after the old one and
  Postfix reads the first). Change settings in `docker-compose.yml`, never
  inside the container.
- **Replacing the certificate**: delete `tls/` and `tls-public/`, `up -d` the
  relay, then recreate Authelia and Vaultwarden (they hold the old CA).
- **Reading mail is not this.** The fleet's mailbox (`purrBrews@`) is read
  over IMAP from Purelymail directly; see the runbook Backlog.
