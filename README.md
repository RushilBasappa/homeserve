# Ragnaforge Home Server

A reproducible, low-maintenance, self-hosted home server across two Debian
laptops — managed with **Docker Compose + Komodo**, reachable privately
(Tailscale) and by family/friends (self-hosted WireGuard), with valid HTTPS on
every app.

> **Design north star:** minimal custom code, off-the-shelf tools, nothing that
> silently goes outdated, and a setup a competent friend could reproduce from
> this repository.

This README is the project's **shareable report** — it grows one section per
phase as the build progresses. See [`PLAN.md`](./PLAN.md) for the full master
plan and [`docs/CONVENTIONS.md`](./docs/CONVENTIONS.md) for how stacks are built.

## Current status

**Phase 4 — Storage — ✅ complete.** The `/srv/nfs` export now carries a
materialized, hardlink-friendly media tree (`media/{movies,tv}`,
`downloads/{complete,incomplete}`, `photos/`, owned `1000:1000` `setgid 2775`),
provisioned idempotently by Ansible and verified consistent across both nodes —
including on-demand automount and server-down boot resilience. The mergerfs + USB
growth path is documented. See
[`docs/runbooks/phase4-storage.md`](./docs/runbooks/phase4-storage.md).

**Phase 3 — Edge, DNS & TLS — ✅ complete.**

Every deployed app now has a friendly, **browser-trusted** `https://<name>.ragnaforge.xyz`
URL, resolved network-wide by an ad-blocking internal DNS, with a private way in
for family/friends. All as Komodo-managed stacks on the Dell:

- **Traefik v3** terminates HTTPS and Host-routes by Docker label; one **Let's
  Encrypt wildcard** `*.ragnaforge.xyz` via Cloudflare DNS-01, persisted and
  auto-renewing. Verified live from a Mac browser; a new route publishes by labels
  alone (no proxy edit, no new cert).
- **AdGuard Home** answers `*.ragnaforge.xyz → 10.0.0.70` for every client and
  blocks ad/tracker domains.
- **Homepage** dashboard at `home.ragnaforge.xyz`; **Cloudflare DDNS** tracks the
  home IP.
- **wg-easy** VPN for family/friends over the **one** public port (`51820/udp`),
  proven end-to-end from an off-network phone; Tailscale carries operators over the
  same subnet route. A public scan shows only UDP 51820.

Preflight verdict: real public IP (not CGNAT) → direct port-forward path.
Full walk-through in [`docs/runbooks/phase3-edge.md`](./docs/runbooks/phase3-edge.md).

Earlier phases: **Phase 0** (scaffolding), **Phase 1** (Ansible + Tailscale
provisioning), **Phase 2** (Komodo orchestration) — ✅ complete.

## Repository layout

| Path | What it holds |
|---|---|
| [`stacks/`](./stacks/) | One directory per Docker Compose stack (the apps). |
| [`provision/`](./provision/) | Lean Ansible to turn a fresh Debian box into a Docker host. |
| [`komodo/`](./komodo/) | Komodo resource-sync definitions (servers + stacks). |
| [`docs/`](./docs/) | Documentation, incl. [`CONVENTIONS.md`](./docs/CONVENTIONS.md). |
| [`PLAN.md`](./PLAN.md) | The master plan — architecture, phases, tooling. |
| `.mise.toml.example` | Placeholder-only secrets template (see below). |
| `.gitignore` | Keeps real secrets and generated artifacts out of version control. |

## Secrets

Real secrets never enter this repository. The tracked
[`.mise.toml.example`](./.mise.toml.example) lists every required secret as an
obvious placeholder. To set up locally:

```sh
cp .mise.toml.example .mise.toml   # .mise.toml is gitignored — fill in real values
```

`mise` renders `.mise.toml` into environment variables that Komodo injects into
stacks. The real `.mise.toml` is ignored by git, so the repo stays safe to share
publicly.

## Quick start

There is nothing to build or run in Phase 0. To validate the scaffolding, follow
[`specs/001-repo-scaffolding/quickstart.md`](./specs/001-repo-scaffolding/quickstart.md).

---

## Build log by phase

Each phase appends its documentation here as it lands. Sections below are
placeholders until their phase is built — see [`PLAN.md`](./PLAN.md) for what
each entails.

### Phase 0 — Foundation & repo scaffolding ✅

Repo skeleton, conventions, and secret-handling pattern in place. This is the
clonable, self-documenting repository everything else builds on.

### Phase 1 — Migration & host provisioning ✅

Two clean Docker hosts (existing data preserved), provisioned with lean Ansible
(`make provision`); Tailscale verified on both nodes. One-time migration steps in
[`docs/runbooks/phase1-migration.md`](./docs/runbooks/phase1-migration.md).

### Phase 2 — Orchestration (Komodo) ✅

**Live on the two hosts.** The Docker hosts are a **centrally managed fleet** with
Komodo (v2):

- **Komodo Core** on the Dell (`komodo-core:2` + MongoDB, cache-capped, state in
  a named volume on the Dell) is the single deploy surface — its UI/API on
  `:9120`, LAN/Tailscale only (no public exposure until Phase 3). Bootstrapped
  out-of-band with `make komodo-core`.
- **Komodo Periphery** on **each** node (`make komodo-periphery`) runs
  `docker compose` locally; Core connects inbound over `https://…:8120`.
- **Git is the source of truth** — the fleet's Servers and Stacks are declared as
  TOML under [`komodo/`](./komodo/); Komodo **ResourceSync** reconciles from this
  repo. A trivial stateless [`whoami`](./stacks/whoami/) stack proved
  deploy-to-a-chosen-node from Core alone.
- **Secrets from `mise`** — stack `${VAR}` references resolve from the gitignored
  `.mise.toml`, kept in sync across nodes with `make sync-secrets`; no real value
  in any tracked file.
- **Deliberate deploys** — manual by default; optional per-stack git webhook
  deferred to Phase 3 (needs Core publicly reachable).

Validated live across all eight scenarios — deploy to a chosen node, git-driven
change, secret injection, node independence (a node down doesn't block the other),
and state persistence across a reboot. The one-time bring-up and the operational
workflow are in
[`docs/runbooks/phase2-komodo.md`](./docs/runbooks/phase2-komodo.md); forward-looking
ideas in [`docs/improvements.md`](./docs/improvements.md).

### Phase 3 — Edge, DNS & TLS ✅

**Live and verified on the Dell** (2026-07-19). Every edge capability is a
Komodo-managed stack pinned to `ragnaforge-dell`, deployed from Core — no ad-hoc
node config. Delivered and running:

- **Traefik v3** ([`stacks/traefik/`](./stacks/traefik/)) — the reverse proxy.
  Discovers apps by Docker labels on the shared external `traefik` network,
  Host-routes `<app>.ragnaforge.xyz`, and redirects HTTP→HTTPS globally.
- **Wildcard TLS** — one Let's Encrypt `*.ragnaforge.xyz` cert via **Cloudflare
  DNS-01**, requested once and reused by every router; `acme.json` persisted on a
  Dell volume; **lifetime-agnostic** auto-renewal (no hardcoded LE lifetime).
- **AdGuard Home** ([`stacks/adguard/`](./stacks/adguard/)) — internal resolver
  answering `*.ragnaforge.xyz → 10.0.0.70` to every client (no split-horizon),
  forwarding the rest upstream, ad/tracker blocklists on. `:53` freed from
  `systemd-resolved` by [`provision/tasks/edge-dns.yml`](./provision/tasks/edge-dns.yml).
- **Homepage** ([`stacks/homepage/`](./stacks/homepage/)) — the dashboard front
  door at `home.ragnaforge.xyz`, config git-declared.
- **Cloudflare DDNS** ([`stacks/cloudflare-ddns/`](./stacks/cloudflare-ddns/)) —
  keeps `vpn.ragnaforge.xyz` on the current public IP.
- **wg-easy** ([`stacks/wg-easy/`](./stacks/wg-easy/)) — the family/friends
  WireGuard VPN; exactly **one** public port (`51820/udp`), admin UI
  LAN/Tailscale-only; pushes the resolver + `10.0.0.0/24` route to clients.
- **Preflight + relay** — a checks-first GO/NO-GO gate
  ([`scripts/preflight-public-endpoint.sh`](./scripts/preflight-public-endpoint.sh),
  `make preflight`) that decides direct port-forward vs. a conditional cloud relay
  ([`relay/README.md`](./relay/README.md)).

Both VPN paths converge: resolver → `10.0.0.70` → subnet route → Traefik →
wildcard cert. **Validated live:** the wildcard cert issued and is browser-trusted
(confirmed from a Mac); publish-by-labels adds a route in seconds with no proxy
edit or new cert; AdGuard resolves names network-wide with ad-blocking; DDNS tracks
the public IP; an off-network phone reached apps over the WireGuard VPN; and a
public scan shows only UDP 51820. Bring-up order, the preflight verdict, and
family/friend onboarding (incl. Fire TV file import) are in
[`docs/runbooks/phase3-edge.md`](./docs/runbooks/phase3-edge.md).

### Phase 4 — Storage ✅

**Materialized and verified on the Dell** (2026-07-19). The Phase-1 NFS export now
has a concrete, hardlink-friendly media tree, proven consistent across both nodes:

- **Standard tree** ([`provision/tasks/storage-layout.yml`](./provision/tasks/storage-layout.yml))
  — `media/{movies,tv}`, `downloads/{complete,incomplete}`, `photos/` under
  `/srv/nfs`, owned `1000:1000` with `setgid 2775` so any media container (PUID/PGID
  1000) writes files the others can hardlink/read. Created idempotently by Ansible
  (second pass `changed=0`), the exact paths Phase 5/6 mount
  ([contract](./specs/005-storage/contracts/media-layout.md)).
- **Verified cross-node** — write-on-Dell/read-and-append-on-Mac is one consistent
  namespace; the Mac's automount activates on demand and does **not** wedge when the
  server is down (recovers on next access). Evidence recorded in the runbook.
- **Golden rule audited** — no stateful app data on the Mac (only the Komodo
  Periphery agent's own state); config stays off NFS.
- **Growth path documented** — mergerfs + USB pooling *under* `/srv/nfs`, export path
  and every app mount unchanged.

Full evidence and the growth procedure in
[`docs/runbooks/phase4-storage.md`](./docs/runbooks/phase4-storage.md).

### Phase 5 — Media stack (ARR + Jellyfin)

_Not started._ Gluetun + qBittorrent, Prowlarr/Radarr/Sonarr/Bazarr, Jellyfin +
Jellyseerr, Configarr.

### Phase 6 — Apps

_Not started._ Immich, Home Assistant, Actual Budget, Vaultwarden, n8n.

### Phase 7 — VPN #2 (wg-easy)

_Not started._ wg-easy on the Dell, router UDP port-forward, subnet routing, Fire
TV onboarding.

### Phase 8 — Monitoring & alerts

_Not started._ Beszel + Uptime Kuma → ntfy push alerts.

### Phase 9 — Backups

_Not started._ Backrest (Restic), pre-backup DB dumps, schedules + restore
procedure.

### Phase 10 — Auto-update & maintenance

_Not started._ Diun update notifications, deliberate Komodo redeploys, optional
Renovate.

### Phase 11 — Documentation & handoff

_Not started._ Finalize this report + `docs/runbooks/`; the reproduce-from-zero
guide.

### Phase 12 — Migrate to the Mac Mini (future)

_Not started._ Consolidate the whole stack onto one 2018 Mac Mini VM; retire NFS
and the laptops.
