#!/usr/bin/env bash
# adguard-setup.sh — complete AdGuard Home's first-run configuration via its HTTP
# API, so the resolver comes up fully configured without the interactive browser
# wizard (US4; research R3; contract dns-resolution).
#
# Reproducible + secret-free: the admin password is read from the environment
# (ADGUARD_ADMIN_PASSWORD, rendered by mise from the gitignored .mise.toml) — never
# hardcoded or committed. AdGuard stores only its own bcrypt hash on the volume.
#
# Run ONCE, on the Dell, after the `adguard` stack is deployed:
#   cd ~/homeserve && mise exec -- ./scripts/adguard-setup.sh
#
# Configures: admin user, DNS on :53 + web on :3000, the wildcard rewrite
# *.ragnaforge.xyz -> 10.0.0.70, Quad9/Cloudflare DoH upstreams + DNSSEC, and the
# AdGuard DNS ad/tracker blocklist. Safe to re-run (install step is skipped once
# configured; the rewrite may duplicate harmlessly).
set -euo pipefail

URL="${ADGUARD_URL:-http://localhost:3000}"
USER="${ADGUARD_ADMIN_USER:-admin}"
PASS="${ADGUARD_ADMIN_PASSWORD:?set ADGUARD_ADMIN_PASSWORD (from .mise.toml)}"
REWRITE_DOMAIN="${ADGUARD_REWRITE_DOMAIN:-*.ragnaforge.xyz}"
REWRITE_ANSWER="${ADGUARD_REWRITE_ANSWER:-10.0.0.70}"

echo "==> First-run configure (admin user; DNS :53; web :3000)"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/control/install/configure" \
  -H 'Content-Type: application/json' \
  -d "{\"web\":{\"ip\":\"0.0.0.0\",\"port\":3000},\"dns\":{\"ip\":\"0.0.0.0\",\"port\":53},\"username\":\"$USER\",\"password\":\"$PASS\"}")
case "$code" in
  200)         echo "    configured" ;;
  400|403|422) echo "    already configured (HTTP $code) — continuing" ;;
  *)           echo "    ERROR: unexpected HTTP $code from install/configure"; exit 1 ;;
esac

AUTH=(-u "$USER:$PASS")

echo "==> Wildcard rewrite $REWRITE_DOMAIN -> $REWRITE_ANSWER"
curl -s "${AUTH[@]}" -X POST "$URL/control/rewrite/add" -H 'Content-Type: application/json' \
  -d "{\"domain\":\"$REWRITE_DOMAIN\",\"answer\":\"$REWRITE_ANSWER\"}" >/dev/null && echo "    ok"

echo "==> Upstreams (Quad9 + Cloudflare DoH) + DNSSEC"
curl -s "${AUTH[@]}" -X POST "$URL/control/dns_config" -H 'Content-Type: application/json' -d '{
  "upstream_dns": ["https://dns.quad9.net/dns-query","https://cloudflare-dns.com/dns-query"],
  "bootstrap_dns": ["9.9.9.9","1.1.1.1"],
  "upstream_mode": "load_balance",
  "enable_dnssec": true
}' >/dev/null && echo "    ok"

echo "==> Enable filtering + AdGuard DNS blocklist"
curl -s "${AUTH[@]}" -X POST "$URL/control/filtering/config" -H 'Content-Type: application/json' \
  -d '{"enabled":true,"interval":24}' >/dev/null || true
curl -s "${AUTH[@]}" -X POST "$URL/control/filtering/add_url" -H 'Content-Type: application/json' \
  -d '{"name":"AdGuard DNS filter","url":"https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt","whitelist":false}' >/dev/null || true
echo "    ok"

echo "==> Done. Verify:  nslookup ${REWRITE_DOMAIN/\*/whoami} $REWRITE_ANSWER"
