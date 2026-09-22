# Native Windows Traefik + Ollama + Authelia

Traffic: LAN client -> roastery:443 -> Authelia on percolator -> localhost:11434.
Both the LAN allowlist and Authelia apply. No unauthenticated route is supplied.
The accompanying Authelia template adds ollama.${DOMAIN} to the existing admin
host list, including its deny fallback; the configured AUTH_POLICY still applies.

## Install into the repository

Copy this bundle's stacks directory into your repository, merging directories.
Review the included percolator Authelia template against any newer local edits.
Download a Windows amd64 Traefik v3 binary from https://github.com/traefik/traefik/releases,
verify its published checksum, and place traefik.exe beside start.ps1.

In stacks/roastery/.env.local, add these values (use your real settings):

```ini
DOMAIN=REPLACE_ME.example.com
LAN_CIDR=192.168.0.0/24
PERCOLATOR_LAN_IP=REPLACE_ME
TRAEFIK_ACME_EMAIL=REPLACE_ME@example.com
```

From stacks/roastery run the existing renderer:

```powershell
.\setup-secrets.ps1
```

The templates are compatible with the existing renderer; none contain secrets.
Never commit the rendered files, token, or data/acme.json (certificate private keys).

## Configure Authelia on percolator

Use the updated stacks/percolator/authelia/config/configuration.yml.template.
Append roastery's fixed LAN IP to FORWARD_AUTH_CLIENTS in percolator's .env.local,
preserving the existing addresses. From stacks/percolator run:

```bash
sudo ./firewall.sh
./render-configs.sh
./compose.sh authelia up -d --force-recreate
```

The ForwardAuth call deliberately goes to percolator:9091, as the repo documents.
The login portal remains https://authelia.${DOMAIN}; it must resolve and work
from the client's browser. Keep port 9091 restricted to the proxy hosts.

## Configure Windows and DNS

As the Windows user who runs Ollama:

```powershell
[Environment]::SetEnvironmentVariable('OLLAMA_HOST', '127.0.0.1:11434', 'User')
```

Quit Ollama from the tray and reopen it. Verify its listening address is
127.0.0.1 using Get-NetTCPConnection -LocalPort 11434 -State Listen.
In Windows Firewall, permit inbound TCP 443 (and 80 for redirects) to the
Traefik executable from your actual LAN CIDR. Port 11434 needs no inbound rule.
Point Pi-hole's ollama.<your-domain> record to roastery's fixed LAN IP.
Do not add a public tunnel or router port forwarding for this LAN-only setup.

Provide the Cloudflare DNS API token to the Traefik process, for example via
CF_DNS_API_TOKEN_FILE pointing to a file outside the repo readable only by your
Windows account. The token needs the same DNS challenge permissions as your
existing Traefik deployments. From stacks/roastery:

```powershell
$env:CF_DNS_API_TOKEN_FILE = 'C:\path\outside-repo\cloudflare-token.txt'
.\traefik\start.ps1
```

This runs in the foreground; keep it running. No Windows service or scheduled
task is installed. Roastery must be awake and Ollama running.

## Verify before relying on it

1. On roastery, curl.exe http://127.0.0.1:11434/api/tags should return JSON.
2. From another computer, connecting directly to roastery:11434 must fail.
3. Without a session, https://ollama.<your-domain>/api/tags must not return model
   JSON: expect an Authelia redirect or an authentication error.
4. Sign in through Authelia as an admin, then open the same URL in the browser:
   it should return model JSON. A household-only account must be denied.
5. If Authelia is unavailable, the endpoint must fail closed.

## API clients and Open WebUI

Authelia ForwardAuth is not an Ollama API-key implementation. A normal Ollama
CLI or Open WebUI backend does not automatically obtain the browser session.
The existing grinder Open WebUI connection to roastery:11434 WILL STOP WORKING
when Ollama binds to localhost. Merely changing its URL to this HTTPS endpoint
does not solve authentication. This bundle intentionally supplies no bypass;
machine-to-machine authentication requires a separate client-compatible design.

## Updates

Pull the repo and rerun setup-secrets.ps1 after changing templates.
Traefik watches the rendered dynamic directory. Restart it for static config
or process environment changes. A git pull alone does not render templates.

Reference: https://www.authelia.com/integration/proxies/traefik/
