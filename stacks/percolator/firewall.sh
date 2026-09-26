#!/usr/bin/env bash
# Same on every node: the logic is in ../_lib/firewall.sh, this node's specifics in node.conf.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$here/../_lib/firewall.sh" "$here" "$@"
