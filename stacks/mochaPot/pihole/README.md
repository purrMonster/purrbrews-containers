# Secondary Pi-hole

## Refresh local app DNS

From `stacks/mochaPot`, `bash ./render-configs.sh` refreshes DNS before rendering
templates. Then run `./compose.sh pihole up -d --force-recreate`.
For the native Ollama route, add roastery's fixed IP and name to
`PIHOLE_DNS_EXTRA_HOSTS` (for example `192.168.0.20 roastery`) on both resolvers,
unless roastery is already in `NODE_IPS` or `PIHOLE_DNS_HOSTS` in `.env.local`.
Existing native router host entries are reused and retained on rendering.
Preserve other semicolon-separated entries.

Both resolvers use the same generated split DNS. From the repository root, run
`bash stacks/_lib/refresh-dns.sh mochaPot` as the ops user, then recreate this
Pi-hole with the node's compose wrapper. A restart alone does not update its
environment. Keep NODE_IPS, DOMAIN and PIHOLE_DNS_EXTRA_HOSTS consistent on both
nodes. See [the network audit](../../../docs/network-audit.md) for rollout order
and checks; verify the secondary from another LAN machine before advertising it.
