# Contract: Secrets Example & Ignore Rules

Defines the guarantees around `.mise.toml.example`, `.mise.toml`, and `.gitignore`.

## `.mise.toml.example` (tracked, placeholder-only)

- MUST enumerate every secret referenced by `PLAN.md`. At minimum:
  - Cloudflare API token (DNS-01 wildcard cert + DDNS)
  - Commercial-VPN WireGuard egress credentials (Gluetun)
  - Tailscale auth key
- Every value MUST be an obvious placeholder (e.g. `CLOUDFLARE_API_TOKEN =
  "changeme-cloudflare-token"`), never a real credential.
- Each entry SHOULD carry a one-line comment naming what it is and where it is used.

## `.gitignore` (tracked)

MUST ignore at least:

```gitignore
.mise.toml
.env
*.env
# generated / rendered artifacts
```

## `.mise.toml` (never tracked)

- Created by the operator by copying `.mise.toml.example` and filling real values.
- MUST be reported ignored by version control.

## Conformance checks (scriptable)

```sh
# Example enumerates the plan's required secrets
for key in CLOUDFLARE TAILSCALE WIREGUARD; do
  grep -qi "$key" .mise.toml.example || echo "example missing secret group: $key"
done

# The real secrets file is ignored
cp .mise.toml.example .mise.toml 2>/dev/null
git check-ignore -q .mise.toml && echo "OK: .mise.toml ignored" || echo "FAIL: .mise.toml NOT ignored"

# No real-looking secret is tracked anywhere (placeholder sweep)
# (manual review: every value in tracked files must read as a placeholder)
```

Non-conformance is any `missing`/`FAIL` line, or any tracked file containing a
real credential.
