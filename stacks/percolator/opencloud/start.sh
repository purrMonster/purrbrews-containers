#!/bin/sh
set -eu
umask 077

# Initialize only a genuinely fresh data/config pair. Missing config after a
# restore must not silently create different IDs and internal credentials.
config=/etc/opencloud/opencloud.yaml
if [ ! -e "$config" ]; then
    if [ -n "$(ls -A /var/lib/opencloud)" ]; then
        echo 'OpenCloud data exists without its config; restore the matching config first.' >&2
        exit 1
    fi
    opencloud init --insecure=false --quiet
fi
if [ ! -s "$config" ]; then
    echo 'OpenCloud config is empty; restore or repair it before starting.' >&2
    exit 1
fi
exec opencloud server
