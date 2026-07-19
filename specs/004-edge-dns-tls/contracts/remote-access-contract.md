# Contract — Remote Access & Public Exposure

The single public entry point, the preflight gate that guards it, the two VPN paths,
and the fallback. Research: R6, R7, R8, R9. Verified by `quickstart.md` (US7/US8).

## Exposure invariant (the whole phase)

- **Exactly one** port is reachable from the public internet: **UDP 51820** (the
  secondary WireGuard VPN). (FR-015, SC-010)
- **Every** other surface — apps, dashboard, resolver, and **all** admin UIs (wg-easy
  `51821`, AdGuard, Traefik dashboard) — **MUST NOT** be reachable from the public
  internet, only over LAN or a VPN path. (FR-015, FR-016, SC-010)
- A public port scan of the home IP **MUST** show only UDP 51820 open. (SC-010)

## Preflight gate (US7 — runs first)

- Before wg-easy is relied on, the preflight **MUST** produce an unambiguous
  **GO/NO-GO** by checking: (a) WAN IPv4 is a real public address, **not** CGNAT
  (`100.64.0.0/10`); (b) external UDP 51820 is reachable; (c) `vpn.ragnaforge.xyz`
  resolves to that IP. (FR-021, SC-013)
- Inconclusive/intermittent ⇒ **NO-GO** — **MUST NOT** report a false GO. (US7 #3)
- **GO** ⇒ direct xFi port-forward path. **NO-GO** ⇒ relay fallback (below), with a
  clear reason. (SC-013)

## Direct path (GO) — obligations

- The router forwards **only** UDP 51820 → the Dell; wg-easy publishes `51820/udp`.
- `vpn.ragnaforge.xyz` tracks the dynamic home IP via DDNS. (FR-011, FR-023)
- Client configs set `Endpoint = vpn.ragnaforge.xyz:51820`, `DNS = 10.0.0.70`,
  `AllowedIPs ⊇ 10.0.0.0/24`. (FR-018, R9)

## Fallback path (NO-GO) — obligations

- A public-IP **VPS relay** on the tailnet **MUST** DNAT inbound `51820/udp` to the
  Dell's Tailscale IP, so remote clients reach wg-easy with **no home inbound port**.
  (FR-022)
- `vpn.ragnaforge.xyz` points at the **VPS** static IP (DDNS not needed on this path).
- The client config and end-user experience **MUST** be identical to the direct path.
  (SC-014)

## Two VPN paths (both reach the edge)

- **Tailscale** (operator) — no forwarded port; Dell advertises `10.0.0.0/24`. (FR-019)
- **WireGuard** (family) — the one forwarded/relayed port; wg-easy pushes DNS + route.
- Both converge: resolver → `10.0.0.70` → subnet route → Traefik → wildcard cert.

## Postconditions (observable)

1. Preflight returns a correct GO/NO-GO before any VPN build; no false GO. (SC-013)
2. A remote device off-LAN/off-Tailscale, using a fresh `.conf` at
   `vpn.ragnaforge.xyz`, connects and loads an app over trusted HTTPS — via
   direct-forward **or** relay, invisibly. (SC-011, SC-014)
3. The same app is reachable over **both** VPN paths. (SC-012)
4. A public scan shows **only** UDP 51820; no admin UI reachable off-LAN. (SC-010, US8 #3/#4)
