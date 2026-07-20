# Implementation Plan: Phase 5 — Media Stack (ARR + Jellyfin/Plex)

**Branch**: `006-media-stack` | **Date**: 2026-07-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-media-stack/spec.md`

## Summary

Stand up the self-service media pipeline on top of the Phase-4 `/srv/nfs` tree and the
Phase-3 edge: a household member requests a title in **Seerr**, it is acquired over
**Proton VPN** (qBittorrent behind **Gluetun**, killswitch + NAT-PMP port forwarding),
imported by **Radarr/Sonarr** as a hardlink into `/srv/nfs/media`, and played from
**both Jellyfin and Plex** (shared library, QuickSync HW transcode). Three operator-facing
capabilities ride on top: a **single manual cascade delete** (via **Maintainerr**) that
removes a title from disk, the download client, the arr apps, both servers, and Seerr;
a **self-maintaining** layer (Prowlarr app-sync, Configarr TRaSH profiles, Cleanuparr,
Huntarr, Byparr); and **reproducible-from-code wiring** with no bespoke scripts.

The design is disciplined by three hard constraints the operator set:

1. **No bespoke scripts, no stale tools.** Deletion is **Maintainerr** (off-the-shelf).
   Proton port-sync is Gluetun's **native** `VPN_PORT_FORWARDING_UP_COMMAND` (not a cron
   script, not a sidecar). Inter-app wiring is Prowlarr native app-sync + deterministic
   env-set API keys + an idempotent post-deploy step. **Buildarr is barred** (unmaintained).
2. **Three configuration planes stay separated** (spec FR-023a): machine (`provision/`,
   untouched here), deployment (Komodo + Compose), application (post-deploy wiring
   **co-located** at `stacks/arr/configure/`, owned by the stack).
3. **Stateful → Dell; the Mac runs only stateless helpers** (golden rule). Because two
   media servers plus the full tool set is heavy for a 7.5 GB node, the rollout is
   **phased by the spec's story priorities** (P1 pipeline+delete first, P2 dual-server +
   automation + stats second) and stateless helpers are pushed to the Mac.

## Technical Context

**Language/Version**: No application language. Infrastructure-as-config: **Docker Compose**
stacks under `stacks/`, deployed by **Komodo** (declared in `komodo/stacks.toml`); the
plane-3 wiring is an **idempotent Ansible playbook** (`ansible.builtin.uri` against app REST
APIs) co-located at `stacks/arr/configure/`, plus **Configarr** (containerised, YAML) for
quality profiles. Secrets via **mise** (`.mise.toml`, gitignored). Markdown runbook under
`docs/runbooks/`.

**Primary Dependencies** (all pinned to explicit image tags, never `:latest` — per Diun/Phase 10 intent):
- **Egress**: `qmcgaw/gluetun` (Proton provider, WireGuard, NAT-PMP), `qbittorrent` (LinuxServer).
- **Acquisition**: `prowlarr`, `radarr`, `sonarr`, `bazarr` (LinuxServer), `unpackerr` (hotio/golift).
- **Servers**: `jellyfin/jellyfin`, `plexinc/pms-docker` — both with `/dev/dri` QuickSync passthrough.
- **Requests/curation**: `seerr-team/seerr` (formerly Jellyseerr/Overseerr, merged 2026), `maintainerr/maintainerr`.
- **Self-maintenance**: `configarr/configarr` (TRaSH), `cleanuparr`, `huntarr`, `byparr` (FlareSolverr successor).
- **Stats**: `jellystat` + its Postgres.

**Storage**: Phase-4 `/srv/nfs` tree (contract `specs/005-storage/contracts/media-layout.md`),
mounted RW where import/write is needed (qBittorrent, servarr), RO on the servers' library
mounts. `media/` + `downloads/` are one filesystem → imports are hardlinks (SC-006). All app
**config** is on **local named volumes on the Dell** (`<app>-config`), never on NFS
(CONVENTIONS "Data placement"). All media containers run `PUID=1000`/`PGID=1000`.

**Testing**: Behavioural validation per `quickstart.md`, mapped to SC-001…SC-011 — including a
**VPN leak test** (SC-002: force the tunnel down, prove zero home-IP egress), a **port-sync
check** (SC-002a), a **six-surface delete verification** (SC-003), a **hardlink assertion**
(SC-006), and an **idempotent-rewire** check (SC-011).

**Target Platform**: `ragnaforge-dell` (10.0.0.70) — all **stateful** stacks (egress+download,
arr, both servers, Seerr, Maintainerr, Jellystat) and the only host with the library on local
disk (so hardlinks and QuickSync live here). `ragnaforge-mac` (10.0.0.71) — **stateless helpers
only** (Byparr, Cleanuparr, Huntarr). LAN `10.0.0.0/24`.

**Project Type**: Infrastructure/documentation monorepo. Changes land in new `stacks/*/`
directories, `komodo/stacks.toml` (+ `komodo/variables.toml`), `.mise.toml.example` (new
placeholders), `docs/CONVENTIONS.md` (three-planes section + ports/URLs), and a new
`docs/runbooks/phase5-media.md`.

**Performance Goals**: Playback is the real target — direct-play whenever the client supports
the container/codec; QuickSync transcode for the rest (1–2 concurrent 1080p streams is the
realistic ceiling on the i3-10110U). NFS-over-gigabit is ample for library reads. Acquisition
throughput is bounded by Proton, not the LAN.

**Constraints**:
- **Egress isolation** — only qBittorrent traffic transits Proton; a tunnel drop blocks it
  entirely (killswitch); no torrent traffic ever reveals the home IP (FR-003, SC-002).
- **RAM budget** — 7.5 GB on the Dell already hosts the edge + Komodo Core. Two media servers
  + arr + helpers do **not** all fit comfortably; mitigated by (a) stateless helpers → Mac,
  (b) phased rollout, (c) an explicit measure-and-decide gate before Plex lands. This is the
  headline risk (see Complexity Tracking).
- **Hardlink filesystem rule** — qBittorrent's download path and the servarr root folders stay
  inside the one Phase-4 filesystem tree (Phase-4 contract guarantee #2).
- **No scripts / no stale tools / three-plane separation** — as above.

**Scale/Scope**: One household (operator + family/friends, read/request only). ~15 containers
across two nodes. Movies + TV only (no music/books/Usenet — spec Out of Scope).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an **unfilled template** — no
ratified principles, so there are no formal gates. The project's *de facto* principles from
`PLAN.md` / `CONVENTIONS.md` are upheld:

- **Stateful → Dell**: every stateful stack is pinned to the Dell; only stateless helpers
  (Byparr/Cleanuparr/Huntarr) run on the Mac. ✅
- **Off-the-shelf, minimal custom code**: deletion = Maintainerr; port-sync = Gluetun native;
  quality = Configarr; wiring = native Prowlarr sync + a thin idempotent Ansible `uri` play.
  No bespoke long-lived scripts; **Buildarr explicitly barred** (stale). ✅
- **Reproducible from git**: stacks in `stacks/`, declared in `komodo/stacks.toml`; wiring in
  `stacks/arr/configure/`; secrets in `mise`. A clean rebuild reproduces the whole stack. ✅
- **No secrets in the repo**: all new secrets are placeholders in `.mise.toml.example`,
  referenced as `${VAR}`. ✅
- **Three configuration planes separated** (spec FR-023a): `provision/` untouched; wiring
  co-located with its stack, post-deploy. ✅

**Result: PASS.** One justified complexity deviation (dual media servers on a small node) is
recorded in Complexity Tracking with its mitigation.

## Project Structure

### Documentation (this feature)

```text
specs/006-media-stack/
├── plan.md              # This file
├── research.md          # Phase 0 — the 11 technical decisions + rationale
├── data-model.md        # Phase 1 — entities (Media item, Request, Download, Deletion collection…)
├── quickstart.md        # Phase 1 — validation runbook (SC-001…SC-011)
├── contracts/
│   ├── stack-inventory.md    # stacks × node × ports × mounts × secrets
│   ├── wiring.md             # the plane-3 connection contract (who connects to whom, with which key)
│   └── deletion-cascade.md   # the six surfaces a single delete must clear (FR-007)
├── checklists/
│   └── requirements.md       # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
stacks/
├── arr/                        # Dell — the acquisition pipeline as ONE deployable unit
│   ├── compose.yaml            #   gluetun + qbittorrent(netns) + prowlarr + radarr + sonarr + bazarr + unpackerr + configarr
│   ├── configure/              #   PLANE 3 — co-located, post-deploy, idempotent
│   │   └── wire.yml            #     Ansible uri: qbit→radarr/sonarr, radarr/sonarr→prowlarr, seerr/bazarr links
│   ├── configarr/config.yml    #   TRaSH quality profiles/custom formats (Configarr input)
│   └── README.md
├── jellyfin/compose.yaml       # Dell — /dev/dri QuickSync
├── plex/compose.yaml           # Dell — /dev/dri QuickSync (Phase-5b; PLEX_CLAIM first-run)
├── seerr/compose.yaml          # Dell — single request front door (backend = Jellyfin)
├── maintainerr/compose.yaml    # Dell — cascade delete (one instance; ref server = Jellyfin)
├── jellystat/compose.yaml      # Dell — watch stats + its Postgres (Phase-5b)
└── media-helpers/compose.yaml  # Mac  — stateless: byparr + cleanuparr + huntarr

komodo/
├── stacks.toml                 # EDIT — declare the new stacks (server pinning per above)
└── variables.toml              # EDIT — non-secret constants if any (e.g. PUID/PGID, TZ)

docs/
├── CONVENTIONS.md              # EDIT — add "three configuration planes"; grow the ports/URL tables
└── runbooks/
    └── phase5-media.md         # NEW — bring-up order, VPN leak test, delete drill, wiring re-run

.mise.toml.example              # EDIT — new placeholders (deterministic API keys, PLEX_CLAIM, qbit)
```

**Structure Decision**: The **acquisition pipeline is one stack** (`stacks/arr/`) because
qBittorrent shares Gluetun's network namespace (`network_mode: service:gluetun`) and the arr
apps are lifecycle-coupled to it — one deployable unit keeps intra-pipeline networking trivial
and lets the plane-3 wiring live **co-located** in `stacks/arr/configure/`. Single-purpose apps
(`jellyfin`, `plex`, `seerr`, `maintainerr`, `jellystat`) stay their own stacks per the naming
convention. Stateless helpers are grouped into one **Mac** stack (`media-helpers`). This is a
deliberate, documented reading of "one stack per app-suite" for the coupled pipeline while
honouring "one stack per app" everywhere else.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **Two media servers (Jellyfin + Plex) on a 7.5 GB node** | Operator's explicit choice (spec US4): Jellyfin = free/open/always-on; Plex = best Fire-TV/remote clients for Phase-7 family. | *One server* is simpler and lighter but drops a capability the operator asked for. Mitigation instead of rejection: **phase it** — Jellyfin lands in P1; Plex is a separate P2 stack gated on a **measured RAM headroom check** (runbook step). If the Dell can't hold both under transcode load, Plex waits for Phase 12 (Mac Mini, 32 GB) — recorded as the escape hatch, not silently assumed to fit. |
| **~15 containers across the pipeline** | Each solves a distinct, operator-selected need (egress, download, index, 2×PVR, subtitles, 2×server, requests, delete, 3×self-maintenance, stats). | A minimal stack (arr + one server) is simpler but omits the deletion mechanism and "modern/self-maintaining" goals that are the whole point of the request. Mitigation: stateless helpers → Mac; helpers are individually optional and deployed last. |
| **Plane-3 wiring hand-encodes app API bodies** | No maintained declarative tool covers download-client / Prowlarr-app / Seerr links (Buildarr is stale, barred). | Manual UI clicks (rejected: not reproducible) or Buildarr (rejected: unmaintained, violates north-star). The Ansible `uri` play is idempotent, co-located, and re-runnable; the accepted cost (version-sensitive payloads) is surfaced as a **visible play failure**, never a silent drift (spec edge case). |
