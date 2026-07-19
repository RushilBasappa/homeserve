# Implementation Plan: Phase 3 — Edge, DNS & TLS

**Branch**: `004-edge-dns-tls` | **Date**: 2026-07-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-edge-dns-tls/spec.md`

## Summary

Give every deployed stack a friendly, browser-trusted `https://<name>.ragnaforge.xyz`
URL and stand up a private way in for family/friends — all as **Komodo-managed
stacks on the Dell**, declared in git under `komodo/` + `stacks/` and deployed from
Core (no ad-hoc node config). Concretely:

1. **Traefik** (`traefik:v3`) — the reverse proxy. Discovers apps by Docker labels
   on a shared external `traefik` network, Host-routes `<app>.ragnaforge.xyz` to the
   right container, and redirects all HTTP→HTTPS globally.
2. **Wildcard TLS** — one Let's Encrypt `*.ragnaforge.xyz` cert via **Cloudflare
   DNS-01**, requested once by Traefik and reused by every router; `acme.json`
   persisted on a Dell volume. **Lifetime-agnostic** auto-renewal (Traefik's built-in
   renewal handles LE's shift to 45/64-day certs; no hardcoded lifetime).
3. **AdGuard Home** — internal resolver. A wildcard **DNS rewrite**
   `*.ragnaforge.xyz → 10.0.0.70` answered identically to every client; all other
   names forwarded upstream; ad/tracker blocklists on. Binds `:53` on the Dell;
   admin UI LAN/Tailscale-only.
4. **Cloudflare DDNS** — a small container keeping the public `vpn.ragnaforge.xyz`
   A-record on the home's current IP (reuses `CLOUDFLARE_API_TOKEN`).
5. **Homepage** — the dashboard front door at `home.ragnaforge.xyz`.
6. **wg-easy** — the secondary WireGuard VPN for family/friends. Publishes **exactly
   one** public port (`51820/udp`, router-forwarded to the Dell), pushes the internal
   resolver + `10.0.0.0/24` route to clients; admin UI LAN/Tailscale-only.
7. **Preflight + fallback** — a checks-first gate (real public IP? not CGNAT? UDP
   51820 reachable?) that decides **direct port-forward** vs. a conditional **cloud
   relay** (a VPS DNAT'ing the WireGuard port to the Dell over Tailscale). Tailscale
   (the operator path) needs no exposed port and is unaffected.

Both VPN paths converge on the same design: resolver returns `10.0.0.70` → subnet
routing carries the client to the Dell → Traefik Host-routes → wildcard cert. Proven
behaviorally with the existing `whoami` stack given routing labels, plus the
dashboard, reached over LAN and **both** VPNs — while a public scan shows only UDP
51820. **No real application services** are deployed here (Phases 5–6).

## Technical Context

**Language/Version**: No application language. Infrastructure-as-config: **Docker
Compose** (`stacks/<app>/compose.yaml`) + **Komodo TOML** resource declarations
(`komodo/`). Images pinned to a visible major/tag (`traefik:v3`, `wg-easy:14`, …),
never `:latest`. `mise` renders secrets into the environment.

**Primary Dependencies**: Traefik v3 (routing + ACME), Let's Encrypt (ACME CA) via
the **Cloudflare** DNS API (DNS-01 + DDNS), AdGuard Home (resolver + blocklists),
a Cloudflare-DDNS container (`favonia/cloudflare-ddns`), Homepage
(`gethomepage/homepage`), wg-easy (`ghcr.io/wg-easy/wg-easy`). All deployed by the
Phase-2 Komodo control plane. Tailscale (Phase 1) provides the operator path and
the fallback relay's transport.

**Storage**: All state on the **Dell** (golden rule): Traefik `acme.json` (cert +
key), AdGuard config/data, wg-easy config (client keys), Homepage config — each a
**local named volume on the Dell** (`traefik-acme`, `adguard-conf`, `adguard-work`,
`wg-easy-config`, `homepage-config`). No NFS in this phase.

**Testing**: No unit suite — behavioral validation per `quickstart.md`, mapped to
SC-001…SC-014: preflight GO/NO-GO; wildcard cert issued & trusted; a labelled stack
reachable by HTTPS name within 30 s; HTTP→HTTPS redirect; unknown host → 404;
resolver returns `10.0.0.70` to every client + blocklist hit; DDNS updates; remote
reach over **both** VPNs; public port scan shows only UDP 51820; secret-free `grep`.

**Target Platform**: The Dell (`ragnaforge-dell`, 10.0.0.70) hosts the entire edge —
Traefik, AdGuard, DDNS, Homepage, wg-easy — pinned there by the resolver answer, the
one forwarded port, and the "stateful → Dell" rule. LAN `10.0.0.0/24` (Xfinity
gateway default), also reachable over Tailscale. The Mac plays no edge role.

**Project Type**: Infrastructure/documentation monorepo. New Komodo-managed stacks
under `stacks/`; declarations in `komodo/stacks.toml`; a shared `traefik` network
created once on the Dell; a preflight script + optional relay definition.

**Performance Goals**: N/A. Practical: the whole edge fits comfortably in the Dell's
7.5 GB alongside Core+Mongo; a label-driven route goes live within seconds of deploy
(SC-002 budgets 30 s); cert issuance is a one-time DNS-01 round-trip.

**Constraints**: **Exactly one** public port (UDP 51820) — everything else
LAN/Tailscale-only (FR-015/16, SC-010). **Secret-free tree** — only `${VAR}` refs;
real values in the gitignored `.mise.toml` (FR-014). **Xfinity reality** — dynamic
IP, possible CGNAT, flaky forward → preflight-gated with a relay fallback (FR-021/22).
**Single-address DNS** — resolver returns `10.0.0.70` to all, no split-horizon
(FR-008). **RAM-lean** on 7.5 GB. **Stateful → Dell.** Deployed via Komodo, not
hand-configured (FR-013).

**Scale/Scope**: 6 edge stacks (traefik, adguard, cloudflare-ddns, homepage, wg-easy,
+ the relabeled `whoami` proof) on 1 node; 1 wildcard cert; 1 shared network; a
handful of `komodo/` + `stacks/` files; 1 preflight script; 1 conditional relay.
Every later app reuses the Traefik label contract established here.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an unpopulated
template — no ratified principles, so there are no formal gates. Applied instead as
the master plan's north stars:

- **Minimal custom code / off-the-shelf tools** — Traefik, AdGuard, wg-easy,
  Homepage, official DDNS image; the only bespoke artifacts are a preflight *check*
  script and Compose/label glue. ✅
- **Nothing silently outdated** — images pinned to a visible major/tag; renewal is
  lifetime-agnostic (survives LE's shortening cadence with no edit). ✅
- **Reproducible by a competent friend** — every capability is a git-declared
  Komodo stack following the existing `stacks/` + `komodo/` model and the
  CONVENTIONS label set; one documented bring-up runbook. ✅
- **Secrets never leak** — reuses the existing `CLOUDFLARE_API_TOKEN`; new secrets
  (wg-easy/AdGuard admin) are placeholders in `.mise.toml.example`, referenced as
  `${VAR}`. ✅
- **Private by default** — one deliberately exposed UDP port, preflight-verified;
  all admin surfaces LAN/Tailscale-only. ✅

**Result**: PASS. **Post-design re-check**: PASS — the design keeps the tree
secret-free, pins all state to the Dell, exposes exactly one port, and adds no
long-lived bespoke service (the preflight is a run-once check; the relay is
conditional and off-the-shelf WireGuard). The two residual risks — Xfinity CGNAT and
freeing `:53` from `systemd-resolved` on the Dell — both have documented handling
(relay fallback; disable the resolved stub listener), so neither blocks the design.

## Project Structure

### Documentation (this feature)

```text
specs/004-edge-dns-tls/
├── plan.md              # This file (/speckit-plan output)
├── spec.md              # Feature specification
├── research.md          # Phase 0 output — decisions & rationale (R1…R12)
├── data-model.md        # Phase 1 output — edge entities & required content
├── quickstart.md        # Phase 1 output — validation scenarios (SC-001…SC-014)
├── contracts/           # Phase 1 output
│   ├── edge-routing-contract.md      # Traefik label contract every app satisfies
│   ├── tls-certificate-contract.md   # wildcard DNS-01 issuance/renewal/persistence
│   ├── dns-resolution-contract.md    # single-address resolver + blocklist + upstream
│   └── remote-access-contract.md     # one exposed port, preflight gate, VPN paths, fallback
├── checklists/
│   └── requirements.md  # Spec quality checklist (16/16 passing)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
homeserve/
├── komodo/
│   ├── stacks.toml                  # EXTEND: [[stack]] traefik, adguard, cloudflare-ddns,
│   │                                #         homepage, wg-easy → server ragnaforge-dell
│   └── variables.toml               # EXTEND: EDGE vars (e.g. VPN_HOSTNAME=vpn.ragnaforge.xyz)
├── stacks/
│   ├── traefik/compose.yaml         # NEW: reverse proxy + ACME DNS-01 (Cloudflare); acme volume
│   ├── traefik/traefik.yaml         # NEW: static config (entrypoints, cert resolver) OR CLI args
│   ├── traefik/dynamic/…            # NEW (opt): TLS options / middlewares (HTTP→HTTPS redirect)
│   ├── adguard/compose.yaml         # NEW: resolver (:53), wildcard rewrite, blocklists; admin LAN-only
│   ├── cloudflare-ddns/compose.yaml # NEW: favonia/cloudflare-ddns → vpn.ragnaforge.xyz
│   ├── homepage/compose.yaml        # NEW: dashboard @ home.ragnaforge.xyz (traefik labels)
│   ├── homepage/config/…            # NEW: services.yaml / settings.yaml (front-door entries)
│   ├── wg-easy/compose.yaml         # NEW: secondary VPN; 51820/udp public; admin 51821 LAN-only
│   └── whoami/compose.yaml          # EDIT: add Traefik labels to prove US1/US2 end-to-end
├── provision/                       # (Phase 1) — may add a task to free :53 on the Dell
│   └── tasks/edge-dns.yml           # NEW (opt): disable systemd-resolved stub listener on Dell
├── scripts/
│   └── preflight-public-endpoint.sh # NEW: US7 checks-first gate → GO/NO-GO (CGNAT, port, DDNS)
├── relay/                           # NEW (conditional): cloud-relay fallback, built only on NO-GO
│   └── README.md                    #   VPS WireGuard/DNAT-over-Tailscale recipe
├── Makefile                         # EXTEND: `make preflight`, `make edge-network` (create net)
├── .mise.toml.example               # EXTEND: WG_EASY_PASSWORD_HASH, ADGUARD_ADMIN_PASSWORD
└── docs/
    └── runbooks/
        └── phase3-edge.md           # NEW: bring-up order, :53 note, preflight, cert, VPN onboarding
```

**Structure Decision**: Reuse the Phase-2 `komodo/` + `stacks/` model unchanged —
every edge capability is a **Komodo-managed stack on the Dell**, declared in
`komodo/stacks.toml` and reconciled by ResourceSync from this repo; none is
bootstrapped out-of-band (the control plane already exists from Phase 2). Two things
sit slightly outside a single stack: (a) the shared external **`traefik` Docker
network**, created once on the Dell (a `make edge-network` target / bring-up step)
so Traefik and every app can join it; and (b) the **preflight script** and
**conditional relay**, which are operator tooling, not long-running services. The
`whoami` stack — Phase 2's throwaway proof — is **relabeled** here to become the
end-to-end HTTPS proof, then removed once real apps land. Secrets reuse the existing
`CLOUDFLARE_API_TOKEN`; new admin secrets are added as placeholders in
`.mise.toml.example` and referenced as `${VAR}`.

## Complexity Tracking

No constitution violations. This section intentionally left empty.
