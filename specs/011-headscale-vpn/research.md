# Research: Self-Hosted Headscale VPN

**Feature**: 011-headscale-vpn | **Date**: 2026-07-25

All decisions below resolve the Technical Context unknowns for a production-grade,
code-reproducible Headscale deployment on the Dell (GO path, per spec Q1).

---

## R1 — Control-plane image & version

**Decision**: Run the **official Headscale** container `docker.io/headscale/headscale:<pinned stable>`
(mirror `ghcr.io/juanfont/headscale`). Pin an explicit tag; **validate at deploy** and record the
running version in the runbook (Diun/Phase-10 house style).

**Rationale**: Off-the-shelf server, no custom code — matches the fleet pattern (one stack per app).

**Caveat (must verify at deploy)**: Headscale **0.27.0** shipped a regression where clients could not
connect after upgrading from 0.26.x ([issue #2870](https://github.com/juanfont/headscale/issues/2870)).
Pin to the latest **0.26.x** stable unless 0.27.x is confirmed fixed. Config keys below are the 0.26
schema; re-diff against `config-example.yaml` for the pinned tag before deploy.

**Alternatives**: Building from source (rejected — no benefit); Tailscale SaaS (rejected — the whole
point is self-hosting the control plane).

---

## R2 — Edge integration: how Headscale sits on :443 (THE critical decision)

**Problem**: The Tailscale control protocol upgrades the HTTP connection with a **non-WebSocket**
`Upgrade: tailscale-control-protocol` header. **Traefik only honors `Upgrade` for `websocket` and
only over HTTP/1.1**; over **HTTP/2 it silently drops the upgrade**, so clients fail to connect. This
is an **open, unfixed** Traefik limitation ([traefik#12609](https://github.com/traefik/traefik/issues/12609)).
The embedded **DERP** relay and **STUN** add their own constraints (STUN is UDP — Traefik can't proxy it).

**Decision (primary)** — keep Traefik on :443 and reuse the existing wildcard cert, but **force
HTTP/1.1 for the Headscale router** so the custom upgrade survives:

1. Headscale runs with **its own TLS disabled** (`listen_addr: 0.0.0.0:8080`, plain HTTP); Traefik
   terminates TLS with the existing **`*.ragnaforge.xyz`** DNS-01 wildcard — no new cert machinery.
2. A Traefik **HTTP router** for `Host(headscale.ragnaforge.xyz)` on `websecure` → `headscale:8080`.
3. A Traefik **TLSOption** `headscale-h1` with `alpnProtocols: ["http/1.1"]`, attached to that router
   (`tls.options=headscale-h1@file`). This removes `h2` from ALPN for this host only, so the control
   protocol negotiates over HTTP/1.1 and the upgrade passes through. Other vhosts keep HTTP/2.
4. Headers: Traefik already sets `X-Forwarded-For` (Headscale's default client-IP source); no extra
   middleware required. Long-lived streams need generous/no idle timeout on the entrypoint.

**Decision (embedded DERP)**: The embedded DERP relay is served by Headscale on the **same :8080**
(HTTP endpoints under `/derp`), so it rides the **same Traefik router** — no separate exposure.
Enable it (`derp.server.enabled: true`) as the always-available relay fallback (FR-008).

**Decision (STUN)**: STUN is **UDP/3478** and **cannot** go through Traefik. Publish it **directly**
from the Headscale container bound to the **LAN IP** (`10.0.0.70:3478:3478/udp`, golden rule / no
public-v6 exposure, FR-015) and **router-forward 3478/udp** to the Dell.

**Fallback (documented, not built in v1)** — if the forced-HTTP/1.1 router still fails the control
handshake on the pinned versions, switch to a Traefik **TCP router with `tls.passthrough=true`** on
`HostSNI(headscale.ragnaforge.xyz)` (same `websecure` entrypoint; TCP+SNI routers coexist with HTTP
routers). Then Headscale must **terminate its own TLS** (built-in ACME **TLS-ALPN-01** over the
passthrough :443, or a mounted cert). This bypasses the HTTP-upgrade bug entirely at the cost of not
reusing the wildcard cert. Captured in the runbook as Plan B.

**Rationale**: Primary path reuses 100% of the existing edge (Traefik on 443, DNS-01 wildcard cert,
file provider already used for Mac routing) and changes the least. The h1 workaround is the
community-standard fix for exactly this Traefik+Headscale symptom.

**Alternatives**: Bare Headscale on its own public port ≠443 (rejected — hotel/corp networks block
non-443, breaks "smooth connections from anywhere"); Caddy/nginx sidecar just for Headscale (rejected —
adds a second reverse proxy to the fleet for one service).

---

## R3 — Public ports & router forwarding (answers the user's explicit question)

**Decision**: Forward exactly two ports on the xFi router to the Dell (`10.0.0.70`):

| Port | Proto | Forwards to | Purpose |
|------|-------|-------------|---------|
| **443** | TCP | Traefik → `headscale:8080` | Handshake, node enroll/login, key/config validation, control stream, **embedded DERP relay** |
| **3478** | UDP | `headscale` container (STUN) | NAT traversal so clients get **direct** P2P links (blocked ⇒ all-relay, still works) |

Optional (not forwarded in v1): **80/tcp** (client captive-portal check / only needed if ever using
HTTP-01 — we use DNS-01, so skip) and **41641/udp** (default client direct-WireGuard port; forwarding
improves direct-link odds to home nodes but is not needed for connectivity).

**Posture change (must be acknowledged)**: This is the **first time 443/tcp is publicly forwarded**
(the old design forwarded only `51820/udp` and *never* 443). Mitigations: the public 443 surface is
only the Headscale vhost + valid TLS; keep the xFi gateway on **Typical Security** so nothing new is
exposed on public IPv6 ([[homeserve-ipv6-exposure-xfinity]]); STUN binds to the LAN IP, not `[::]`.

**Rationale**: 443 + 3478 is Headscale's documented minimum public surface for handshake + direct
connectivity with relay fallback.

---

## R4 — DNS: friendly names keep working; MagicDNS disabled

**Decision**:
- **Disable MagicDNS** (`dns.magic_dns: false`). We do **not** want `*.tailnet` names; we want the
  existing `*.ragnaforge.xyz` names resolved by **AdGuard**.
- Push **AdGuard as a split (restricted) resolver** for the lab domain only:
  `dns.nameservers.split: { "ragnaforge.xyz": ["10.0.0.70"] }`. Clients keep their normal DNS for
  everything else (split-tunnel DNS, better than a global override) — the Headscale analogue of
  wg-easy's `WG_DEFAULT_DNS`.

**Rationale**: Reuses the unchanged "name→address→app" flow (AdGuard answers `10.0.0.70` for any
`*.ragnaforge.xyz`; Traefik serves the app with the wildcard cert). Disabling MagicDNS avoids a
`base_domain` collision with the split-routed `ragnaforge.xyz` and keeps DNS behavior identical to the
LAN experience. `server_url` host (`headscale.ragnaforge.xyz`) is resolved publicly via Cloudflare, so
it is reachable *before* the tunnel/AdGuard exist (no chicken-and-egg).

**Alternatives**: MagicDNS on with `base_domain` outside `ragnaforge.xyz` (rejected — adds a second
name scheme for no user benefit); global nameserver override (rejected — hijacks all client DNS).

---

## R5 — Reaching LAN apps: the Dell as an approved subnet router

**Decision**: The **Dell** joins its own Headscale tailnet as a **subnet router** advertising
`10.0.0.0/24` (`tailscale up --login-server https://headscale.ragnaforge.xyz --advertise-routes=10.0.0.0/24`).
The route is **auto-approved** via policy `autoApprovers.routes` for the Dell's tag
(`tag:subnet-router`), so remote clients reach `10.0.0.70` (AdGuard + Traefik + every app) exactly like
on the LAN. `net.ipv4.ip_forward=1` is already set on the Dell (was a wg-easy prereq).

**Rationale**: All apps and the resolver live at `10.0.0.70`; a single approved /24 route reproduces
the LAN reachability wg-easy provided via `WG_ALLOWED_IPS: 10.0.0.0/24`.

**Alternatives**: Per-host routes (rejected — /24 is the existing model); running a subnet router in a
separate container (rejected — the Dell host is already the node and gateway).

---

## R6 — Access policy (ACL): owner vs guests, and the honest limit

**Decision**: Ship a **policy file** (HuJSON, `policy.mode: file`) with two users:
- **`owner`** — full access (`*:*`).
- **`guests`** — access restricted to the LAN edge only: destination `10.0.0.0/24:443` (plus DNS to
  `10.0.0.70:53`). This blocks guests from SSH (:22), Komodo (:9120/:8120), NFS (:2049/:111), AdGuard
  admin (:3000), etc. — everything except the HTTPS front door.
- `autoApprovers.routes` approves `10.0.0.0/24` advertised by `tag:subnet-router` (the Dell).

**Honest limitation (documented, not a defect)**: Network ACLs gate **host:port**, not **vhost**. All
apps share `10.0.0.70:443` behind Traefik host-routing, so ACLs **cannot** scope a guest to *one* app
by name. True per-app scoping relies on each app's own auth (the existing model). FR-009 is satisfied
at the network layer (guests reach only the edge, not fleet internals); per-app is app-level auth.
This is called out in the runbook so expectations are correct.

**Rationale**: Least-privilege at the layer the tool actually controls; matches how the fleet already
gates apps (app auth behind a shared edge).

---

## R7 — Guest onboarding: pre-auth keys + per-platform custom login server

**Decision**: Owner issues **pre-authorized keys** scoped to `guests`, **single-use** and
**time-boxed** (e.g. `headscale preauthkeys create --user guests --expiration 24h`), optionally
`--reusable` for a shared family device. Guest flow per platform:
- **Android / Windows / Linux / macOS (CLI)**: `tailscale login --login-server https://headscale.ragnaforge.xyz --authkey <key>` (or the desktop app's "Use custom coordination server").
- **iOS / macOS (app)**: the Tailscale app supports a **custom coordination server** setting; the guest
  enters `https://headscale.ragnaforge.xyz` then authenticates with the key/URL.
- **Owner** enrolls the same way and (optionally) uses a small **web admin UI** to mint keys without the
  CLI (see R8).

**Rationale**: Pre-auth keys are the non-technical "one paste/scan" path that replaces wg-easy's
`.conf`/QR. Expiry + single-use gives revocation and time-boxing (FR-010).

**Note**: Some platforms surface the custom-server field in different places; the guest guide
(`quickstart.md` / runbook) gives exact per-platform steps with screenshots-in-words. There is no
Fire TV Tailscale path as clean as wg-easy's file import — flagged as a known onboarding gap for
TV-class devices (out of scope to solve in v1).

---

## R8 — Optional web admin UI for key management

**Decision (optional, include)**: Add **`ghcr.io/gurucomputing/headscale-ui`** as a second container,
fronted by Traefik at `headscale-ui.ragnaforge.xyz`, **LAN/Tailscale-only** (normal wildcard, **never**
router-forwarded — same posture wg-easy's admin UI had). It calls Headscale's API (an API key stored in
`mise`) so the owner can create/expire pre-auth keys and see nodes without the CLI.

**Rationale**: Directly supports FR-006 (owner issues guest enrollments easily) and FR-019 (operable).
Optional because the CLI fully suffices; the UI is a convenience.

**Alternatives**: Headplane / other UIs (equivalent; pick one, pin it). No UI (acceptable — CLI-only).

---

## R9 — State, persistence & secrets

**Decision**:
- **Database**: **SQLite** at `/var/lib/headscale/db.sqlite` on a **Dell-local named volume**
  (`headscale-data`). Sufficient for <50 nodes (well within a family homelab); simplest to back up.
- **Keys**: `noise_private_key`, DERP `private_key`, and the SQLite DB all live on the same Dell volume
  — protected fleet **state** (golden rule: state on the Dell). Backup = snapshot that volume.
- **Secrets**: the **API key** (for the UI) and any `mise`-managed values come from the gitignored
  `.mise.toml` forwarded to the Periphery env; **nothing secret is committed**. The Headscale
  `config.yaml` and `policy.hujson` are **non-secret** and ship in the repo (inline `configs:` per
  [[homeserve-inline-configs-need-recreate]] — editing them needs a container **recreate**).

**Rationale**: Mirrors the fleet's storage + secrets conventions exactly.

**Alternatives**: Postgres (rejected — over-provisioned for this scale; adds a container + backup
surface). External secret store (rejected — fleet uses `mise`).

---

## R10 — Config validation before public exposure (FR-011)

**Decision**: Gate bring-up on **`headscale configtest`** (validates `config.yaml`) and a
**policy check** (`headscale policy check` where available, else deploy-time load) run inside the
container before the router forward is opened. An **Ansible assert** co-located at
`stacks/headscale/configure/` (Phase-5/6 house style) probes: control endpoint TLS + the
`/health`-style liveness, STUN reachability, and that the Dell node's route is approved. Fail closed.

**Rationale**: Catches a broken config before external clients depend on it (the spec's explicit
"config validation" step).

---

## R11 — Decommission wg-easy; preserve Tailscale as stopped fallback (FR-002/003/017)

**Decision**:
- **Remove** the `wg-easy` stack (`stacks/wg-easy/`), its `komodo/stacks.toml` `[[stack]]` decl, its
  Traefik admin route, and the **`51820/udp`** router forward. `DestroyStack` then delete files.
- **Preserve Tailscale**: leave the Dell's `tailscale` client installed and its tailnet identity intact;
  **`tailscale down`** (stop the SaaS-connected session) after Headscale is proven. Rollback = re-point
  the Dell client back to Tailscale SaaS (`tailscale up`) — old owner path restored in minutes, no
  re-provisioning.
- **Relay VPS (FR-016) fallback**: the `relay/` recipe is updated to DNAT **443/tcp + 3478/udp** to the
  Dell **over the preserved Tailscale tailnet** (the relay already rides Tailscale, which we keep) —
  documentation only in v1, not built.

**Rationale**: Clean removal + a genuine, fast rollback path; the preserved Tailscale doubles as the
transport for the CGNAT relay fallback.

---

## Open items carried to tasks (none blocking)

- Confirm the pinned Headscale tag's `config-example.yaml` key names (0.26 vs 0.27 schema drift) at
  task time; adjust `config.yaml` accordingly.
- Confirm the forced-HTTP/1.1 router carries the control handshake on the pinned client/server pair
  during live bring-up; if not, execute the R2 **Plan B** (TCP/SNI passthrough).
