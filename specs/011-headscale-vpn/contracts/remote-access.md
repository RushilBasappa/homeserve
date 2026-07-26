# Contract: Remote Access (control-plane exposure, client onboarding, ACL, DNS/routes)

What an external client must be able to do — enroll, validate, connect — and the invariants that keep it
correct and safe. This is the interface the migration must preserve/replace (was wg-easy; now Headscale).

## Control-plane exposure (the public surface)

| Requirement | Contract |
|---|---|
| Public name | `headscale.ragnaforge.xyz` — Cloudflare A record → home public IP (via `cloudflare-ddns`), resolvable **before** the tunnel exists |
| Transport | `443/tcp` (TLS by Traefik, `*.ragnaforge.xyz` wildcard) + `3478/udp` (STUN, direct from container) |
| Upgrade fix | Headscale router forced to **HTTP/1.1** (TLSOption `alpnProtocols: ["http/1.1"]`) so the `Upgrade: tailscale-control-protocol` survives Traefik (traefik#12609). Fallback: TCP/SNI passthrough. |
| DERP | embedded, on the same `443` route; always-available relay when direct P2P fails |
| TLS in-container | **disabled** (`server_url` https + plain `listen_addr`); the expected `WRN listening without TLS` log is benign |

## Client onboarding (must stay "one paste/scan" for guests)

| Step | Contract |
|---|---|
| Key issue | owner runs `headscale preauthkeys create --user guests --expiration 24h` (or the UI); single-use, time-boxed; `--reusable` for a shared device |
| Enroll | client points at the custom server: `tailscale login --login-server https://headscale.ragnaforge.xyz --authkey <key>` (or the app's "custom coordination server" field on iOS/macOS) |
| Validate | client completes handshake + key validation against `headscale.ragnaforge.xyz` and appears in `headscale nodes list` |
| Connect | direct P2P where possible (STUN), else DERP relay — **must succeed either way** (FR-008) |

## DNS & routes pushed to clients (reproduce the LAN experience)

| Item | Contract |
|---|---|
| Resolver | split DNS: `ragnaforge.xyz → 10.0.0.70` (AdGuard); client keeps its own DNS otherwise; MagicDNS **off** |
| Route | `10.0.0.0/24` advertised by the Dell (`tag:subnet-router`), **auto-approved** via `autoApprovers.routes` |
| Result | remote device resolves `*.ragnaforge.xyz` → `10.0.0.70` and reaches Traefik + apps with the valid wildcard cert — identical to on-LAN |

## Access policy (ACL) invariants

| User | May reach | May NOT reach |
|---|---|---|
| `owner` | everything (`*:*`) | — |
| `guests` | `10.0.0.0/24:443` (edge HTTPS) + `10.0.0.70:53` (DNS) | SSH :22, Komodo :9120/:8120, NFS :2049/:111, AdGuard admin :3000, any non-443 host service |

**Limitation (by design, R6)**: ACLs gate host:port, not vhost — a guest reaching `:443` can, at the
network layer, reach any vhost Traefik serves. Per-app scoping relies on each app's own auth (unchanged
fleet model). Documented in the runbook.

## Invariants (must all hold)

- **INV-1**: The only public inbound after this feature is `443/tcp` + `3478/udp` → Dell. `51820/udp` is
  removed. Nothing else is forwarded.
- **INV-2**: No new service is reachable on the Dell's public **IPv6** (Xfinity Typical Security; STUN
  bound to `10.0.0.70`, not `[::]`). Verified by an external v6 scan (SC-009).
- **INV-3**: All control-plane **state** (DB + keys) is on the Dell (`headscale-data`); no secret is
  committed; config/policy are non-secret and inline.
- **INV-4**: **Tailscale is preserved** (installed, identity intact, session stopped) — rollback = one
  `tailscale up` on the Dell (FR-017).
- **INV-5**: The control server is a **single point of failure**: if it is down, existing peers keep
  passing traffic on valid keys; only new enroll/re-key fails. Documented; state is backed up.
- **INV-6**: Config is **validated before exposure** (`headscale configtest` + assert) — fail closed.
