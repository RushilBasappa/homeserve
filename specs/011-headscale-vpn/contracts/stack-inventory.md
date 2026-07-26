# Contract: Stack Inventory (stack × node × services × ports × volumes × secrets)

The interface this feature adds to (and removes from) the fleet. Komodo declares the stack in
`komodo/stacks.toml`. Headscale is the fleet's control plane; unlike every other app it is
**deliberately reachable from the internet** — the only fleet service besides the (removed) wg-easy that
takes a router forward. All state lives in a **Dell-local named volume** (golden rule).

## Stacks

### Added — `headscale`

| Stack | Compose file | Node | Services | Subdomain(s) | Routed via | Volumes | Notes |
|---|---|---|---|---|---|---|---|
| `headscale` | `stacks/headscale/compose.yaml` | Dell | `headscale` (+ optional `headscale-ui`) | `headscale` (public) ; `headscale-ui` (LAN/VPN-only) | Traefik HTTP router **forced HTTP/1.1** → `headscale:8080` | `headscale-data` | control plane; TLS off in-container (Traefik terminates); embedded DERP on :8080; STUN on :3478/udp |

- **`headscale`** — official image, pinned stable tag (avoid 0.27.0 regression, R1). Joins the external
  `traefik` network for its route; `listen_addr: 0.0.0.0:8080` (plain HTTP). Config `config.yaml` +
  `policy.hujson` ship **inline** (`configs:`) — editing needs a container **recreate**.
- **`headscale-ui`** (optional, R8) — `ghcr.io/gurucomputing/headscale-ui`, LAN/Tailscale-only Traefik
  route (**never** forwarded); talks to the Headscale API with an API key from `mise`.
- **Isolated** — own directory, container, volume; removing it leaves the rest of the fleet untouched.

### Removed — `wg-easy`

| Action | Target |
|---|---|
| DestroyStack + delete | `stacks/wg-easy/compose.yaml`, `stacks/wg-easy/` |
| Remove decl | `komodo/stacks.toml` `[[stack]]` name = `wg-easy` |
| Remove router forward | `51820/udp` on the xFi router |
| Remove edge route | `wg.ragnaforge.xyz` (admin UI) |
| Keep | Tailscale client + tailnet identity on the Dell (stopped via `tailscale down`, R11) |

## Ports

| Port | Proto | Service | Exposure | Why |
|---|---|---|---|---|
| **443** | TCP | Traefik → `headscale:8080` | **PUBLIC (router-forwarded)** | control plane: handshake, enroll/login, key/config validation, control stream, embedded DERP relay |
| **3478** | UDP | `headscale` (STUN) | **PUBLIC (router-forwarded)**; container bound to `10.0.0.70` | NAT traversal for direct P2P (blocked ⇒ all-relay) |
| 8080 | TCP | `headscale` | internal (`traefik` net only) | plain-HTTP control endpoint; **not** published to host, **not** forwarded |
| 9090 / gRPC | TCP | `headscale` metrics/grpc | internal only | never exposed |
| 443 (route) | TCP | `headscale-ui` | LAN/VPN-only via Traefik | admin UI; **never** forwarded |
| ~~51820~~ | ~~UDP~~ | ~~wg-easy~~ | **REMOVED** | old WireGuard endpoint retired |

**Router forwards after this feature**: `443/tcp` + `3478/udp` → Dell (`10.0.0.70`). `51820/udp` removed.
**IPv6**: keep Xfinity **Typical Security**; STUN binds to the LAN IP, not `[::]` ([[homeserve-ipv6-exposure-xfinity]]).

## Volumes & state

| Volume | Contents | Backup |
|---|---|---|
| `headscale-data` | `db.sqlite`, `noise_private_key`, DERP `private_key` | snapshot the volume (DB + keys = the whole tailnet) |

## Secrets (from `mise`, gitignored; never committed)

| Secret | Used by | Notes |
|---|---|---|
| `HEADSCALE_API_KEY` | `headscale-ui` | Headscale API auth; UI-only, optional |

Non-secret and committed: `config.yaml`, `policy.hujson` (inline in compose).

## Host prerequisites (Dell)

- `net.ipv4.ip_forward=1` — already applied (was a wg-easy prereq); required for the subnet router.
- Tailscale client installed (already) — re-pointed at Headscale as the `10.0.0.0/24` subnet router.
