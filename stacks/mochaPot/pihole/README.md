# Secondary Pi-hole

## Refresh local app DNS

Both resolvers use the same generated split DNS. From the repository root, run
`bash stacks/_lib/refresh-dns.sh mochaPot` as the ops user, then recreate this
Pi-hole with the node's compose wrapper. A restart alone does not update its
environment. Keep NODE_IPS, DOMAIN and PIHOLE_DNS_EXTRA_HOSTS consistent on both
nodes. See [the network audit](../../../docs/network-audit.md) for rollout order
and checks; verify the secondary from another LAN machine before advertising it.
