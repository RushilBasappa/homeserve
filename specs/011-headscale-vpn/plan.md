# Implementation Plan: Self-Hosted Headscale VPN (replace wg-easy; retire Tailscale SaaS)

**Branch**: `011-headscale-vpn` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-headscale-vpn/spec.md`

## Summary

Stand up **Headscale** — a self-hosted Tailscale control server — as **one isolated stack** under
`stacks/headscale/`, following the house pattern (Compose under `stacks/<app>/`, Traefik edge, inline
`configs:`, Dell-local named volume, secrets from `mise`, a runbook + optional Ansible assert). It
**replaces both** remote-access VPNs: the failing **wg-easy** (removed) and the owner's dependence on
**Tailscale's SaaS** control plane (Tailscale kept installed but stopped as a fast rollback). Remote
clients keep using the **standard Tailscale apps**, re-pointed at `headscale.ragnaforge.xyz`.

The design decisions that carry the spec's risk:

1. **Traefik + the control-protocol upgrade (the critical one, R2).** The Tailscale control channel uses
   a **non-WebSocket** `Upgrade: tailscale-control-protocol`, which **Traefik drops over HTTP/2**
   (open bug traefik#12609). Fix: an HTTP router for `headscale.ragnaforge.xyz` with a **TLSOption
   forcing `alpnProtocols: ["http/1.1"]`** on that host only, so the upgrade survives while every other
   vhost keeps HTTP/2. Traefik terminates TLS with the **existing `*.ragnaforge.xyz` DNS-01 wildcard**;
   Headscale runs plain HTTP on `:8080` (TLS off). **Plan B** if the handshake still fails on the pinned
   versions: a Traefik **TCP router with `tls.passthrough=true`** on `HostSNI` + Headscale terminating
   its own TLS. Documented in the runbook.
2. **The public port surface changes (R3).** For the first time **443/tcp is router-forwarded** (old
   design: only `51820/udp`). Headscale's minimum public surface is **443/tcp** (control + embedded DERP
   relay) **+ 3478/udp** (STUN, which Traefik cannot proxy — published straight from the container bound
   to `10.0.0.70`). This posture change is accepted and mitigated (vhost-only 443 surface + valid TLS;
   Xfinity stays on Typical Security; STUN not on `[::]` → no public-v6 leak).
3. **Friendly names unchanged (R4).** MagicDNS **off**; push **AdGuard** as a **split resolver**
   (`ragnaforge.xyz → 10.0.0.70`). Steps 1 & 3 of the "name→address→app" flow are reused verbatim — this
   feature only changes *how remote clients get onto the network*.
4. **LAN reachability via a subnet router (R5).** The Dell joins its own tailnet advertising
   `10.0.0.0/24`, **auto-approved** by policy, so clients reach `10.0.0.70` (AdGuard + Traefik + apps)
   exactly like on the LAN — the Headscale analogue of wg-easy's `WG_ALLOWED_IPS`.
5. **Least-privilege ACL (R6)** with an honest limit: `owner` full; `guests` → edge `:443` + DNS only
   (blocks SSH/Komodo/NFS/AdGuard-admin). Network ACLs gate host:port, **not** vhost — per-app scoping
   stays app-level auth.
6. **Non-technical onboarding (R7):** time-boxed, single-use **pre-auth keys** + the client's custom
   coordination-server flow; an optional **web UI (R8)** lets the owner mint keys without the CLI.
7. **State & secrets (R9):** **SQLite** + key files on the Dell-local `headscale-data` volume (protected
   state, golden rule); only an optional UI **API key** comes from `mise`; `config.yaml`/`policy.hujson`
   are non-secret and inline.
8. **Validate before exposure (R10):** `headscale configtest` + an Ansible assert gate the router
   forward; fail closed.
9. **Clean removal + rollback (R11):** DestroyStack wg-easy and delete it + its `51820/udp` forward;
   `tailscale down` on the Dell (kept installed); rollback = `tailscale up`.

**Excluded from v1** (deferred/documented, not built): a **standalone DERP** (embedded suffices <50
nodes); the **relay-VPS** CGNAT fallback (recipe updated to DNAT 443+3478 over the preserved Tailscale
tailnet, but not deployed — it's the NO-GO path); Postgres; Fire-TV-class onboarding parity.

## Technical Context

**Language/Version**: No application code authored. Infrastructure-as-config: a **Docker Compose** stack
under `stacks/headscale/`, deployed by **Komodo** (declared in `komodo/stacks.toml`). Traefik dynamic
config (TLSOption) added to the existing **file provider**. One idempotent **Ansible** assert at
`stacks/headscale/configure/` (Phase-5/6 house style). Secrets via **mise** (`.mise.toml`, gitignored).
A new runbook at `docs/runbooks/headscale.md`; `docs/networking-explained.md` + `relay/README.md`
updated for the new ports.

**Primary Dependencies** (pin explicit tags; **verify/bump at deploy**):
- **headscale**: `docker.io/headscale/headscale:<pinned stable>` — control plane; HTTP `:8080` (TLS off),
  embedded DERP on `:8080`, STUN on `:3478/udp`. **Avoid 0.27.0** (connect regression, issue #2870);
  pin latest **0.26.x** unless 0.27.x is confirmed fixed. Re-diff `config-example.yaml` for the pinned
  tag before deploy.
- **headscale-ui** (optional): `ghcr.io/gurucomputing/headscale-ui` — LAN/VPN-only admin UI.
- Reused unchanged: **Traefik** (edge + file provider), **AdGuard** (`10.0.0.70`), **cloudflare-ddns**
  (the `headscale` public name), the **`*.ragnaforge.xyz`** DNS-01 wildcard, the **Tailscale** client
  (re-pointed as subnet router; preserved as rollback).

**Storage**: SQLite `db.sqlite` + `noise_private_key` + DERP `private_key` on the Dell-local named
volume `headscale-data`. No NFS, no Mac.

**Testing**: `headscale configtest`; an Ansible assert (`stacks/headscale/configure/`) probing control
TLS + liveness, STUN reachability, and route approval; live bring-up drills (owner enroll off-LAN,
guest enroll on cellular) recorded in the runbook.

**Target Platform**: Linux (the Dell) under Komodo/Docker; clients = official Tailscale apps
(desktop + mobile).

**Project Type**: Homelab infrastructure (single stack + edge wiring), not an application.

**Performance/Scale**: Family homelab, **<50 active nodes** — embedded DERP + SQLite are within budget.
SC targets: cold-connect app reachable <30 s (SC-001); guest enroll <5 min (SC-002); relay fallback
100% where direct impossible (SC-003).

**Constraints**: One public 443 surface = the Headscale vhost only; no new public-v6 service (SC-009);
all state on the Dell; no committed secrets; Tailscale preserved for rollback.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is the **unfilled template** (placeholders only) — no ratified
principles to gate against. In its place, the plan is checked against the fleet's **de-facto house
rules** (from CLAUDE.md/memory + prior features), all of which it satisfies:

| House rule | Status |
|---|---|
| One stack per app under `stacks/<app>/`, isolated | ✅ `stacks/headscale/` |
| Komodo `[[stack]]` declaration, git-pulled | ✅ added; wg-easy decl removed |
| Traefik edge; friendly `*.ragnaforge.xyz` name | ✅ `headscale.ragnaforge.xyz` (+ UI) |
| State on the Dell (golden rule); no NFS/Mac state | ✅ `headscale-data` volume |
| Secrets from `mise`, never committed; configs inline | ✅ only optional API key; config/policy inline |
| Bind published ports to the LAN IP, not `[::]`; no public-v6 exposure | ✅ STUN → `10.0.0.70`; Typical Security |
| Code-reproducible, runbook, no undocumented manual step (portability goal) | ✅ runbook + assert + updated docs |

**Justified deviation (Complexity Tracking)**: Headscale is the **first deliberately internet-exposed**
fleet service (443 forwarded), breaking the old "443 is never forwarded / one public UDP port" rule.
This is intrinsic to a self-hosted control plane and is the explicit ask; mitigated per R3/INV-1/INV-2.

Re-check after Phase 1: **PASS** — no new violations introduced by the design artifacts.

## Project Structure

### Documentation (this feature)

```text
specs/011-headscale-vpn/
├── plan.md              # This file
├── research.md          # Phase 0 — R1–R11 decisions
├── data-model.md        # Phase 1 — control-plane entities
├── quickstart.md        # Phase 1 — validation drills
├── contracts/
│   ├── stack-inventory.md   # stack × ports × volumes × secrets; wg-easy removal
│   └── remote-access.md     # exposure, onboarding, ACL, DNS/routes, invariants
└── checklists/
    └── requirements.md      # spec quality checklist (all pass)
```

### Source Code (repository root)

```text
stacks/headscale/
├── compose.yaml                 # headscale (+ optional headscale-ui); inline config.yaml + policy.hujson
└── configure/                   # optional Ansible assert (control TLS + liveness, STUN, route approval)
    └── assert.yml

stacks/wg-easy/                  # REMOVED (DestroyStack, then delete)
└── compose.yaml                 # deleted

komodo/
├── stacks.toml                  # + [[stack]] headscale ; − [[stack]] wg-easy
└── (traefik file provider)      # + TLSOption headscale-h1 (alpnProtocols http/1.1) + headscale router

docs/
├── runbooks/headscale.md        # NEW — deploy, ports/forwarding, guest onboarding, key rotation,
│                                #        backup/restore, rollback to Tailscale, Plan B (passthrough)
├── networking-explained.md      # UPDATED — replace wg-easy scenario with Headscale; new port table
└── ...

relay/README.md                  # UPDATED — NO-GO fallback DNATs 443+3478 over the preserved Tailscale
```

**Structure Decision**: Single new isolated stack (`stacks/headscale/`) + edge wiring in the existing
Traefik file provider and `komodo/stacks.toml`, plus the wg-easy removal and doc updates. No new
top-level areas; mirrors every prior Phase-3/5/7 app.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| First internet-forwarded 443 (breaks "443 never forwarded") | A self-hosted control plane must be publicly reachable for handshake/enroll from any network | Non-443 port (blocked on hotel/corp nets → not "smooth from anywhere"); relay-only (still needs a public control endpoint somewhere) |
| Forced HTTP/1.1 on one Traefik router (loses h2 for that host) | Traefik drops the non-WebSocket control-protocol upgrade over h2 (traefik#12609) | Plain HTTP/2 router (silently fails the handshake); second reverse proxy just for Headscale (adds fleet complexity) |
| STUN published outside Traefik (UDP) | Traefik cannot proxy UDP; STUN needs udp/3478 public for direct P2P | Route via Traefik (impossible); disable STUN (forces all-relay, worse connections) |
