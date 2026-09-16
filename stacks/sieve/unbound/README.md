# Unbound

A recursive, DNSSEC-validating resolver. Pi-hole is its only client. Image
`klutchell/unbound:main` (Unbound 1.26; distroless, so there is no shell inside).

## How it's wired

- **Own network.** `sieve_dns` (`172.31.53.0/28`), fixed address `172.31.53.2`, and
  **no published ports**. Pi-hole uses host networking, so it reaches the container
  over the bridge. Nothing on the LAN can.
- **Default config, narrowed.** The image's config already handles root hints, DNSSEC
  trust anchors, prefetching and serve-expired. `config/access-control.conf` is merged
  in and only restricts who may query.
- **Access list.** Unbound applies the *most specific* matching rule, whatever the
  order. The image allows `192.168.0.0/16`, `172.16.0.0/12` and `10.0.0.0/8`, so the
  overrides are more specific:
  - refuse `172.31.53.0/28` (the `sieve_dns` subnet);
  - allow `172.31.53.1/32` (the host, i.e. Pi-hole);
  - refuse `192.168.0.0/24` (the LAN).

  A broad `0.0.0.0/0 refuse` would do nothing here: it's less specific than the
  image's `/16` allow.

## Checks

From sieve (`dig` is in `bind9-dnsutils`):

```bash
dig @172.31.53.2 cloudflare.com +short     # answer: the host is allowed
dig @172.31.53.2 dnssec-failed.org         # SERVFAIL: validation is on
sudo docker run --rm --network sieve_dns alpine sh -c \
  'apk add -q bind-tools && dig @172.31.53.2 cloudflare.com'   # status: REFUSED
```

Tested before first deploy: the host gateway was answered and another container on
`sieve_dns` got `REFUSED`.

## Notes

- **Not `read_only`.** Unbound rewrites its trust anchor (`root.key`) as the root key
  rolls over.
- **The first queries after a start are slow** (a cold cache walks from the root).
  Prefetch and serve-expired keep it fast after that.
- **If you change `DNS_SUBNET`**, update both addresses in `config/access-control.conf`
  and `UNBOUND_IP`. Then recreate Unbound and Pi-hole.
