# Shared Compose services

Four Linux nodes (grinder, mochaPot, percolator and sieve) extend these definitions:

| Definition | Settings owned here | Settings owned by each node app |
|---|---|---|
| `komodo-periphery.yml` | Image, connection settings, absolute mounts, restart policy | `./keys` mount |
| `scrutiny-collector.yml` | Image, capabilities, schedule, hub endpoint, udev mount, restart policy | Disk devices and mochaPot's `collector.yaml` mount |

Edit a shared definition once to update all four consumers. Keep Core and
Periphery versions aligned, and keep the collector version aligned with cellar's
Scrutiny hub. Cellar's combined stacks and roastery's Windows services retain
their own definitions because their service layout or platform differs.

The node's `docker-compose.yml` uses native Compose `extends`; the existing
`compose.sh` commands and environment precedence still apply. Deploy the whole
repository, not an isolated app folder: the relative `../../_shared/` reference
must be present. These definitions are inputs, not standalone stacks.

Keep relative bind mounts in the node file. Compose rebases paths in an extended
file relative to that file; moving `./keys` here would change its source directory.
Shared mounts use absolute paths. See the
[Compose extends documentation](https://docs.docker.com/compose/how-tos/multiple-compose-files/extends/).
Keep route labels in node app files too: DNS discovery reads those files directly.

The eight original definitions are preserved under
`Deprecated/2026-10-09/stacks/<node>/<app>/docker-compose.yml` at the repository root.
They are historical snapshots, outside active stack discovery.
