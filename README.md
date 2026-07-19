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

**Phase 2 — Orchestration (Komodo) — ✅ complete.**

The two Debian hosts are a **centrally managed fleet**. Komodo Core runs on the
Dell (its state in a Mongo volume on the Dell), with a Periphery agent on both
nodes; the fleet's servers and stacks are declared in git under
[`komodo/`](./komodo/) and reconciled by Komodo ResourceSync. A stack deploys to
a chosen node **from Core alone** — no SSH, no manual `docker compose` on the
node. Secrets come from the gitignored `.mise.toml` (kept in sync across nodes
with `make sync-secrets`); the tracked tree stays secret-free. Proven live with a
trivial `whoami` test stack across all eight validation scenarios (deploy,
git-driven change, secret injection, node independence, reboot persistence). Real
application services arrive from Phase 3 onward.

Earlier phases: **Phase 0** (foundation & repo scaffolding) and **Phase 1** (host
provisioning via Ansible + Tailscale) — ✅ complete.

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

### Phase 3 — Edge, DNS & TLS

_Not started._ Traefik + Let's Encrypt wildcard (Cloudflare DNS-01), AdGuard Home
internal DNS, Cloudflare DDNS, Homepage dashboard.

### Phase 4 — Storage

_Not started._ Dell NFS server + volume conventions; the mergerfs + USB growth
path.

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
