# Fleet audit — 2026-09-18

Three passes covered provisioning and DNS, proxy/authentication/firewall paths,
and configuration generation/operations. Read-only SSH and unauthenticated HTTP
checks then compared the repository with the running fleet. Percolator is
192.168.0.11, confirmed by the owner; the attached infrastructure PDF's .15 is
outdated. The PDF also predates the per-node Traefik deployment.

## Confirmed on the running fleet

| Finding | Evidence | State |
|---|---|---|
| Mac used inconsistent DNS servers | Wi-Fi resolver list was .10, .14, 1.1.1.1; .14 timed out, public DNS returned NXDOMAIN for Authelia | Changed this Mac to .10 only; 10 consecutive normal HTTPS requests to Authelia returned 200 from .11 with valid TLS |
| IPv6 is active despite intended IPv4-only operation | All five nodes have an RA-derived IPv6 default route and DNS server; neighbor MAC matches the IPv4 gateway .1 | Router configuration and existing host profiles still need correction |
| Secondary DNS unavailable from Mac | .13 times out on LAN DNS; queries on mochaPot itself succeed; port 53 is listening | Inspect UFW/routing; do not advertise .13 until external queries pass |
| Host DNS still uses public/bootstrap resolvers | Four nodes use 1.1.1.1/9.9.9.9 plus router IPv6 DNS; mochaPot uses .10/1.1.1.1 plus router IPv6 DNS | Existing profiles still need migration; public fallback cannot resolve private names |
| Homepage route unavailable | Direct-IP HTTPS with correct SNI/Host returns proxy-style 404 | Need privileged container status/provider logs |
| Cellar HTTPS certificate invalid | Komodo and Scrutiny serve `TRAEFIK DEFAULT CERT` | Need Traefik/ACME logs; do not disable TLS verification as a fix |
| mochaPot bridge/config drift | .env.local says 172.30.13.0/24; host has no bridge in that subnet | Inspect `docker network inspect mochapot_net`; align PROXY_SUBNET and HA trusted_proxies with actual network, or schedule a network migration |
| Nodes run different repository revisions | sieve 27366d4; percolator/mochaPot 05fe657; grinder f5d1486; cellar e3039a9 | Reconcile versions before rollout; observed tracked edits were executable-bit changes |

All 29 app names returned the expected IPv4 addresses through sieve. Forced-IP
HTTPS probes found 26 responses of 200/302, Homepage's 404, and the two cellar
certificate failures. A 302 to authentication does **not** verify the protected
backend or a successful login. No authenticated user journeys were tested.

## Follow-up after router change

The owner disabled router IPv6 assignment. Subsequent checks on sieve,
percolator and mochaPot show no IPv6 default route, but NetworkManager still
retains the previously learned link-local IPv6 DNS server. Host DNS migration
remains necessary; turning off advertisements is not evidence that all clients
have already discarded learned settings.

The supplied privileged diagnostics confirmed:

- mochaPot UFW has no DNS port 53 allowance. It also contains broad, manually
  added web-port allowances, rather than the tracked scoped firewall rules.
- `docker ps -a --filter name=homepage` returns no containers on percolator.
- cellar Traefik repeatedly cannot connect to its Docker socket. Its deployed
  Compose file was v3.2 with no socket mount; the host socket exists.

Historical direct staging (not activated, superseded by the Git-only delivery
requirement): the current cellar Traefik Compose
file, and mochaPot's secondary Pi-hole Compose file plus the shared DNS refresh
helpers. Original Compose files were backed up under each ops user's
`~/.cache/purrbrews-audit/`. No containers have been recreated. The remainder
of the repository changes are still local only. Secondary DNS must both receive
local records and allow LAN DNS before being used by clients.

## Verification after activation

The owner ran the secondary DNS/firewall, cellar Traefik recreation, and
Homepage startup commands. Follow-up checks passed all 58 A-record comparisons
(29 app names on each resolver), plus public UDP/TCP resolution on the secondary.
Authelia's AAAA and HTTPS/TYPE65 queries return NOERROR with no answers on both.
Homepage now redirects to authentication with valid TLS; Scrutiny also redirects
with a valid Let's Encrypt certificate. These checks do not prove authenticated
backend functionality. Komodo's direct port 9120 returns 200, but its HTTPS
hostname still serves Traefik's default certificate; fresh provider logs and
container status are needed.

All five nodes still report public/bootstrap DNS and the previously learned
IPv6 resolver. The Git-delivered `init/use-lan-dns.py` verifies both resolvers
from each node before saving/applying only DNS properties. It ignores automatic
IPv4/IPv6 DNS and removes the explicit IPv6 DNS list without bringing the
interface down or applying unrelated saved profile changes:

```sh
python3 /opt/purrbrews/init/use-lan-dns.py --dry-run
sudo python3 /opt/purrbrews/init/use-lan-dns.py
```

This changes resolver selection, not IPv6 addressing. The router advertisements
have been disabled by the owner, and new provisioning already disables IPv6.
Containers with resolver snapshots may still require recreation. The script
supports explicit domain/server/IP arguments for installations with different
settings. Its use of active-device DNS modification follows the
[NetworkManager CLI documentation](https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/nmcli.html).

## Repository changes

- Both Pi-holes now use one local-record generator based on the installed fleet
  inventory and tracked Traefik routes. Missing nodes and conflicting hostname
  destinations fail before replacing configuration. Extras remain configurable.
- Each local app gets both `address=` and `local=` rules. `filter-AAAA` remains
  enabled. The local rule prevents forwarding other query types (including HTTPS
  records) for these app names. The whole public zone is not suppressed, so
  unrelated public names and ACME TXT queries remain available.
- Primary DHCP advertises the two fleet DNS servers. Deploy and verify the
  secondary **first**. Both instances must use identical NODE_IPS, DOMAIN and
  extra local host definitions. This does not replicate Pi-hole blocklists.
- Secondary DHCP/DHCPv6 and NTP are explicitly disabled, overriding persisted UI
  settings. Home Assistant and Music Assistant explicitly use the LAN resolvers.
- New host network profiles disable IPv6; Unbound uses IPv4 transport. These
  changes do not alter existing router advertisements or active host profiles.
- mochaPot allows proxy-bridge access to its three host-networked web services;
  grinder allows its actual proxy bridge to reach ESPHome. Verify the bridge
  subnet before applying rules, especially on existing installations.
- All five config renderers use the same implementation: missing/empty/placeholder
  variables fail, each app's secrets are isolated, root/node/app precedence is
  preserved, outputs default to mode 0600, and failed renders preserve the old
  file. Direct app templates such as restic/rclone.conf load the right secrets.
- Secondary Pi-hole's SSO route is in the admin-only group policy.
- An unconfigured backup job exits nonzero instead of falsely reporting success.
  This does not create a backup implementation.

## Rollout and verification

The repository changes require activation after Git delivery. All code and
configuration updates must be committed, pushed, and pulled through Git. Any
earlier direct staging must be preserved in a Git stash and replaced by the
committed version during the pull. Remote sudo requires a
password unavailable to this session. Preserve node-local settings/secrets and
any local changes when pulling the reviewed commit. Do not reset the
remote checkouts. Commands below run on their named hosts as barista, from
`/opt/purrbrews`, after the reviewed changes have been pulled from Git.

1. On the main router, inspect LAN IPv6 Router Advertisement/RDNSS and DHCPv6
   settings. For the owner's IPv4-only design, disable those advertisements.
   Inspect both router and Pi-hole DHCP: only one should serve leases. Configure
   clients with .10 only until .13 passes LAN tests; never add a public resolver
   as fallback for private names. Renew leases/reconnect clients afterwards.
2. On mochaPot, compare its configured PROXY_SUBNET with:

   ```sh
   sudo docker network inspect mochapot_net --format '{{json .IPAM.Config}}'
   sudo ufw status numbered
   ```

   Set PROXY_SUBNET to the actual IPv4 bridge subnet and make Home Assistant's
   `http.trusted_proxies` agree. A network migration is an alternative but
   requires downtime; do not remove a live Docker network blindly.

   ```sh
   bash stacks/_lib/refresh-dns.sh mochaPot
   sudo bash stacks/mochaPot/firewall.sh
   bash stacks/mochaPot/compose.sh pihole config --quiet
   bash stacks/mochaPot/compose.sh pihole up -d --force-recreate
   ```

   From another LAN machine, set DOMAIN to the private zone locally, then verify:

   ```sh
   dig @192.168.0.13 "authelia.$DOMAIN" A +time=2 +tries=1
   dig @192.168.0.13 "authelia.$DOMAIN" AAAA +time=2 +tries=1
   dig @192.168.0.13 "authelia.$DOMAIN" TYPE65 +time=2 +tries=1
   dig +tcp @192.168.0.13 "authelia.$DOMAIN" A +time=2 +tries=1
   dig @192.168.0.13 example.com A +time=2 +tries=1
   ```

   Require A=.11, AAAA/TYPE65=NOERROR with no answers, and successful public
   resolution. Only after this succeeds should clients use .10 and .13 together.
3. On sieve, regenerate DNS and recreate Pi-hole, then repeat the tests against
   .10. This also updates the DHCP DNS option when sieve DHCP is enabled.

   ```sh
   bash stacks/_lib/refresh-dns.sh sieve
   bash stacks/sieve/compose.sh pihole config --quiet
   bash stacks/sieve/compose.sh pihole up -d --force-recreate
   bash stacks/sieve/compose.sh unbound up -d --force-recreate
   ```

4. On each host, inspect the active NetworkManager profile. Set IPv4 DNS to the
   verified local resolvers, ignore automatic DNS, and set `ipv6.method disabled`.
   Apply at a console or with a recovery plan: reactivating a profile can interrupt
   SSH. Do not rerun full provisioning just to change DNS. Recreate affected
   containers after host DNS changes; restarting does not replace their DNS
   configuration snapshot. Percolator's proxy-network Authelia alias already
   provides local OIDC resolution to containers on that network.
5. On each affected node, render with `bash stacks/<node>/render-configs.sh` and
   inspect the exit status. Complete missing settings before starting services.
   Recreate consumers of changed bind-mounted files (including Traefik/Authelia),
   since atomic file replacement does not update an existing file bind mount.
   On grinder, run its firewall script under sudo. Validate each changed compose
   project with `config --quiet` before `up -d --force-recreate`.
6. Diagnose Homepage and cellar certificates with container status and Traefik
   logs. Do not replace certificates or recreate apps speculatively. Check
   Cloudflare API token permissions, ACME storage and DNS challenge errors based
   on the actual log messages; secrets must not be pasted into the public repo.

## Privileged diagnostics still needed

Run these from the Mac in your own terminal; enter sudo passwords only in the
terminal, and review logs for credentials before sharing output:

```sh
ssh -t barista@192.168.0.13 'sudo ufw status numbered'
ssh -t barista@192.168.0.11 'sudo docker ps -a --filter name=homepage --format "{{.Names}} {{.Status}}"'
ssh -t barista@192.168.0.12 'sudo docker logs --tail 60 traefik 2>&1'
```

These are read-only. The SSH user can connect, but this session cannot perform
password-protected sudo. The root-required rollout remains pending.

## Remaining operational gaps

Database dump jobs on percolator and configured restic sources are absent; the
backup chain described in the PDF is a design, not a proven working restore path.
Backing up hot PostgreSQL/Mongo data directories is not a substitute for consistent
exports. Source mounts, retention, offsite OAuth/crypt setup and a restore test
need confirmation before implementing or enabling jobs. Existing rclone runtime
credentials require preservation when re-rendering its config.

Gatus checks primary DNS but does not currently assert secondary DNS parity.
Router settings, browser secure-DNS overrides, and lease behavior are outside
this repository. These must be verified on affected clients as well as servers.
Several READMEs contain pre-migration descriptions; this dated audit records
current evidence without treating those older statements as operational facts.

## Checks and references

`python3 -m unittest discover -s tests -v` covers real router discovery, duplicate
and missing-node errors, primary/secondary parity, DHCP advertisement, atomic
render failure, permissions, app secret isolation, direct-app secret loading,
all template shapes, bridge firewall dry runs, and shell syntax. YAML parsing and
`git diff --check` supplement these. Docker/Compose and application config
validation require a Docker-equipped host and have not run on this Mac.

- [dnsmasq manual](https://dnsmasq.org/docs/dnsmasq-man.html): `address`, `local`,
  filtering and DHCP options.
- [Pi-hole configuration](https://docs.pi-hole.net/ftldns/configfile/): FTLCONF
  environment settings and custom dnsmasq lines.
- [NetworkManager IPv6 settings](https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/settings-ipv6.html):
  automatic configuration and disabled method.

## Komodo follow-up

Fresh Traefik logs identify the router as `Host(komodo.REPLACE_ME.example.com)`
and show ACME rejecting that invalid domain. Cellar's current local DOMAIN is
filled in and Komodo's secrets do not override it; the 25-hour-old container
still carries its creation-time labels. Recreate only `komodo-core` using the
current Compose settings. A restart cannot update labels. Cellar's wrapper now
checks resolved Compose JSON for placeholders before startup and reports field
paths without printing secret values.

```sh
cd /opt/purrbrews/stacks/cellar
bash compose.sh komodo up -d --no-deps --force-recreate komodo-core
```

## Confirmed DHCP outage

The owner confirmed DHCP is disabled on all routers/switches and network
isolation is off. Pi-hole's runtime `dhcp.active` is also false; sieve's firewall
already permits UDP 67. There is therefore no identified DHCP service on the
intended flat LAN. This explains lease acquisition/renewal failures, but does
not prove every Wi-Fi association or work-VPN failure has the same cause.
`stacks/sieve/enable-dhcp.sh` provides the explicit Git-delivered handover.
Activation and a client lease test remain necessary. Both Pi-holes currently
resolve `mail.tcs.com` successfully; test the office laptop again after DHCP
recovery and capture exact Azure hostnames if failures persist.

## Permanent DHCP role configuration

At the owner's request, sieve now fixes `FTLCONF_dhcp_active: "true"` directly
in Compose; mochaPot fixes it to `"false"`. This overrides persisted Pi-hole
settings and ignores legacy `PIHOLE_DHCP_ACTIVE=false` values in node-local
env files. Every deployment of sieve's Pi-hole will therefore enable DHCP.
Routers must remain DHCP-disabled. Lease range, gateway and lease duration
remain configurable in the node's env file. Recreate the primary Pi-hole once
to activate the new Compose setting; subsequent redeployments retain it.
