#!/usr/bin/env bash
# preflight-public-endpoint.sh — the checks-first GO/NO-GO for the public VPN
# endpoint (US7, research R7; contract remote-access §"Preflight gate").
#
# Runs BEFORE wg-easy is relied on and prints ONE unambiguous verdict:
#   GO     → the home has a usable public inbound; use the direct xFi port-forward
#            path (forward UDP 51820 → the Dell; DDNS keeps vpn.ragnaforge.xyz
#            current).
#   NO-GO  → CGNAT / no reachable inbound / inconclusive; use the cloud-relay
#            fallback (relay/README.md) and point vpn.ragnaforge.xyz at the VPS.
#
# Checks:
#   1. Public IPv4 is a REAL routable address, not CGNAT (100.64.0.0/10) or a
#      private range (double-NAT signal).
#   2. External UDP 51820 is reachable from OUTSIDE the home.
#   3. vpn.ragnaforge.xyz resolves to that public IP (DDNS is current).
#
# Golden rule: INCONCLUSIVE ⇒ NO-GO. Never report a false GO (US7 #3).
#
# The UDP-51820 reachability check cannot be done honestly from the home host
# itself — inbound reachability must be observed from an EXTERNAL vantage. Run an
# external probe (phone hotspot / a friend's machine / an online UDP checker while
# the port is temporarily forwarded and wg-easy is up) and feed the result in:
#
#     EXTERNAL_UDP_51820=open  make preflight     # confirmed reachable
#     EXTERNAL_UDP_51820=closed make preflight    # confirmed unreachable
#
# With no result supplied, check 2 is INCONCLUSIVE and the verdict is NO-GO.

set -euo pipefail

WG_HOSTNAME="${WG_HOSTNAME:-vpn.ragnaforge.xyz}"
WG_UDP_PORT="${WG_UDP_PORT:-51820}"

# --- output helpers -------------------------------------------------------------
if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); GREEN=$(printf '\033[32m'); RED=$(printf '\033[31m')
  YELLOW=$(printf '\033[33m'); RESET=$(printf '\033[0m')
else
  BOLD=""; GREEN=""; RED=""; YELLOW=""; RESET=""
fi
pass() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
fail() { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"; }
warn() { printf '  %s?%s %s\n' "$YELLOW" "$RESET" "$1"; }

# Overall state: any fail/inconclusive flips the verdict to NO-GO.
VERDICT_GO=1
REASONS=()
downgrade() { VERDICT_GO=0; REASONS+=("$1"); }

printf '%sPreflight — can the home host a public VPN endpoint?%s\n\n' "$BOLD" "$RESET"

# --- 1. Public IPv4 vs CGNAT -----------------------------------------------------
printf '%s1. Public IPv4 (CGNAT check)%s\n' "$BOLD" "$RESET"
PUBLIC_IP="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
if [ -z "$PUBLIC_IP" ]; then
  # Fallback provider.
  PUBLIC_IP="$(curl -fsS --max-time 10 https://ifconfig.me 2>/dev/null || true)"
fi

is_cgnat_or_private() {
  # Args: dotted IPv4. Returns 0 if in CGNAT (100.64/10) or RFC1918 private space.
  local ip="$1" o1 o2
  o1="${ip%%.*}"; o2="${ip#*.}"; o2="${o2%%.*}"
  case "$ip" in
    10.*) return 0 ;;                                  # 10.0.0.0/8
    192.168.*) return 0 ;;                             # 192.168.0.0/16
  esac
  if [ "$o1" = "172" ] && [ "$o2" -ge 16 ] && [ "$o2" -le 31 ]; then return 0; fi   # 172.16/12
  if [ "$o1" = "100" ] && [ "$o2" -ge 64 ] && [ "$o2" -le 127 ]; then return 0; fi  # 100.64/10 CGNAT
  return 1
}

if [ -z "$PUBLIC_IP" ]; then
  warn "could not determine the external IP (no network / provider down)"
  downgrade "external IP undetermined"
elif ! printf '%s' "$PUBLIC_IP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  warn "external lookup returned a non-IPv4 value: $PUBLIC_IP"
  downgrade "external IP not IPv4 (CGNAT/IPv6-only signal)"
elif is_cgnat_or_private "$PUBLIC_IP"; then
  fail "external IP $PUBLIC_IP is CGNAT/private — no direct inbound possible"
  downgrade "CGNAT/private external IP ($PUBLIC_IP)"
else
  pass "external IP $PUBLIC_IP is a routable public address"
fi
echo

# --- 2. External UDP 51820 reachability -----------------------------------------
printf '%s2. External UDP %s reachability%s\n' "$BOLD" "$WG_UDP_PORT" "$RESET"
case "${EXTERNAL_UDP_51820:-}" in
  open|OPEN|yes|true|1)
    pass "external probe reports UDP $WG_UDP_PORT reachable" ;;
  closed|CLOSED|no|false|0)
    fail "external probe reports UDP $WG_UDP_PORT NOT reachable"
    downgrade "external UDP $WG_UDP_PORT unreachable" ;;
  *)
    warn "no external probe result (set EXTERNAL_UDP_51820=open|closed) — INCONCLUSIVE"
    warn "run an external probe: forward UDP $WG_UDP_PORT, start wg-easy, then from"
    warn "off-network confirm a WireGuard handshake to $WG_HOSTNAME:$WG_UDP_PORT"
    downgrade "external UDP $WG_UDP_PORT reachability inconclusive" ;;
esac
echo

# --- 3. DDNS resolves to the public IP ------------------------------------------
printf '%s3. DDNS — %s resolves to the public IP%s\n' "$BOLD" "$WG_HOSTNAME" "$RESET"
resolve_a() {
  if command -v dig >/dev/null 2>&1; then
    dig +short A "$1" @1.1.1.1 2>/dev/null | grep -Em1 '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true
  else
    # nslookup fallback.
    nslookup "$1" 1.1.1.1 2>/dev/null | awk '/^Address: /{print $2}' | grep -Em1 '^[0-9]+\.' || true
  fi
}
DDNS_IP="$(resolve_a "$WG_HOSTNAME")"
if [ -z "$DDNS_IP" ]; then
  fail "$WG_HOSTNAME does not resolve (no A record yet?)"
  downgrade "$WG_HOSTNAME unresolved"
elif [ -n "$PUBLIC_IP" ] && [ "$DDNS_IP" = "$PUBLIC_IP" ]; then
  pass "$WG_HOSTNAME → $DDNS_IP (matches the public IP)"
elif [ -n "$PUBLIC_IP" ]; then
  warn "$WG_HOSTNAME → $DDNS_IP but public IP is $PUBLIC_IP (DDNS lagging?)"
  downgrade "$WG_HOSTNAME ($DDNS_IP) != public IP ($PUBLIC_IP)"
else
  warn "$WG_HOSTNAME → $DDNS_IP (public IP unknown; cannot compare)"
  downgrade "cannot confirm $WG_HOSTNAME matches the public IP"
fi
echo

# --- Verdict --------------------------------------------------------------------
printf '%s────────────────────────────────────────%s\n' "$BOLD" "$RESET"
if [ "$VERDICT_GO" -eq 1 ]; then
  printf '%s%s VERDICT: GO %s — direct xFi port-forward path.\n' "$BOLD" "$GREEN" "$RESET"
  printf '  Forward ONLY UDP %s → the Dell; deploy wg-easy; keep DDNS running.\n' "$WG_UDP_PORT"
  exit 0
else
  printf '%s%s VERDICT: NO-GO %s — use the cloud-relay fallback (relay/README.md).\n' "$BOLD" "$RED" "$RESET"
  printf '  Reasons:\n'
  for r in "${REASONS[@]}"; do printf '    - %s\n' "$r"; done
  printf '  Stand up the VPS relay, point %s at the VPS static IP, then deploy wg-easy.\n' "$WG_HOSTNAME"
  exit 1
fi
