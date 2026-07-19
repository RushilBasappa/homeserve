# Contract — Internal DNS Resolution

How `*.ragnaforge.xyz` names resolve for every client, and how ad-blocking behaves.
Research: R3, R9. Verified by `quickstart.md` (US4).

## Obligations (the resolver — `adguard`)

- **MUST** answer **any** `<name>.ragnaforge.xyz` with `10.0.0.70` — the **same
  answer to every client** (LAN, Tailscale, WireGuard): no split-horizon. (FR-008)
- **MUST** forward all other domains to upstream resolution (the resolver is not a
  walled garden — ordinary public domains still resolve). (FR-008, SC-005)
- **MUST** be usable by VPN clients such that `ragnaforge.xyz` names resolve for remote
  clients (not defeated by DNS-rebind protection — a private-IP answer for our own
  domain is expected/allowed). (FR-009)
- **MUST** block a maintained ad/tracker blocklist network-wide **without** breaking
  resolution of legitimate domains. (FR-010, SC-005)
- The admin UI **MUST** bind LAN/Tailscale-only (never the forwarded public port).
  (FR-016)

## Dependencies / obligations on the network

- `10.0.0.70` (the Dell) **MUST** be reachable from a client that received it — over
  the LAN directly, and over each VPN via **subnet routing** (R9): Tailscale advertises
  `10.0.0.0/24`; wg-easy pushes `AllowedIPs ⊇ 10.0.0.0/24`. A resolver answer without a
  route is a **routing** failure, not a wrong answer. (FR-009, FR-019)
- Clients **MUST** be pointed at the resolver: LAN via DHCP/manual; VPN clients via the
  VPN's pushed DNS (wg-easy `WG_DEFAULT_DNS=10.0.0.70`; Tailscale split-DNS). (FR-018)
- The Dell's `:53` **MUST** be freed from `systemd-resolved` before AdGuard binds it.

## Postconditions (observable)

1. A device using the resolver gets `10.0.0.70` for every `*.ragnaforge.xyz` name;
   ordinary public domains still resolve; a known ad/tracker domain is **blocked**.
   (SC-005)
2. The **same** app name resolves and loads over **both** VPN paths, each returning
   `10.0.0.70` and reaching the same Traefik/cert. (SC-012)

## Failure behavior

- Resolver down ⇒ clients fall back per their configured secondary DNS (defined
  behavior, not total DNS loss). (Edge case)
