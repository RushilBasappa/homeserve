# Phase 0 — Research: Media & System Stats (Tautulli + Beszel)

Technical decisions that resolve the plan's unknowns. Each: **Decision · Rationale ·
Alternatives considered**. Constraints carried in from the spec: dashboards-only (no push),
read-only Plex, golden rule (state → Dell), lightweight footprint, reproducible-from-git.

---

## R1 — Media watch stats tool: Tautulli

**Decision**: Use **Tautulli** (`ghcr.io/tautulli/tautulli`, pinned tag) on the Dell for Plex
watch stats. It provides now-playing sessions with per-stream user/title/device/bitrate and the
**play-method** (direct play / direct stream / **transcode**), plus per-user history in a local
SQLite DB.

**Rationale**: It is the canonical Plex stats tool, actively maintained, single-container,
read-only against Plex, and directly surfaces the transcode-vs-direct-play signal the spec calls
the most actionable number on a 2-core box (US1, SC-001). It has first-class **Homepage widget**
support (R4), so the front-door now-playing tile is native, not custom. Named in PLAN.md Phase 6.

**Alternatives considered**: **Jellystat** — dropped in Phase 5 as unused; Jellyfin-only, so it
would not cover the Plex-primary audience (accepted gap, spec Assumptions). **Grafana + Plex
exporter** — multi-GB, rejected by FR-015. **Plex's own dashboard** — no persistent per-user
history, no transcode breakdown at a glance.

---

## R2 — Fleet metrics tool + architecture: Beszel (hub + agents)

**Decision**: Use **Beszel** — `henrygd/beszel` (hub) on the Dell and `henrygd/beszel-agent` on
**both** the Dell and the Mac. The hub serves the web UI (port 8090) and stores metric history in
an embedded **PocketBase/SQLite** DB under `/beszel_data` (Dell named volume `beszel-data`). Each
agent reports host metrics (CPU/RAM/disk %/network/temps) and, via a read-only `docker.sock`
mount, **per-container** CPU/RAM. The hub is fronted by Traefik; agents have **no** web UI.

**Connection & graceful-down**: the hub **polls each agent** over the LAN (agent listens on its
port, default 45876; Dell agent reachable locally, Mac agent at `MAC_LAN_IP:45876`). When the Mac
is asleep/off the hub simply can't reach that agent → the system renders **down/stale**, and it
**auto-recovers** when the Mac returns — satisfying FR-010/SC-006 with no special handling. This
matches the known Mac behaviour ([[homeserve-ragnaforge-mac-node]]): NotOk when asleep is normal.

**Rationale**: Beszel is explicitly the PLAN.md Phase-6 choice — one fleet view, per-container
stats, configurable thresholds, tiny footprint (hub ~50 MB, agent ~15 MB). Chosen over Netdata
(heavier, cloud-nudgey) and Prometheus/Grafana (multi-GB) to fit the ~7.5 GB nodes (FR-019).

**Both nodes are Debian Linux — no macOS caveat**: `ragnaforge-mac` is Apple *hardware* running
**Debian Linux** (the same OS as the Dell), not macOS ([[homeserve-ragnaforge-mac-node]]). So the
Mac agent is an ordinary Linux agent — identical in shape to the Dell agent, using
`network_mode: host`. There is no Docker-Desktop VM layer and no macOS limitation. **Coverage**:
host networking + the shared kernel give real CPU/RAM/network + per-container stats for both nodes;
**root-disk % and temperatures** need the host filesystem/sensors passed into the container
(host-fs mount + `EXTRA_FILESYSTEMS`, `hwmon` passthrough) — a normal Linux-container detail, added
per the pinned Beszel version at deploy, applying equally to the Dell agent. (Also version-sensitive
and validated at deploy: the agent listen-port env — `LISTEN` on newer Beszel, `PORT` on older.)

**Alternatives considered**: **Netdata** (per-node, heavier, pushes toward Netdata Cloud);
**Glances** (no multi-node hub / thresholds story as clean); **Prometheus + node-exporter +
cAdvisor + Grafana** (the "real" stack — rejected as multi-GB and operationally heavy, FR-015,
revisit post-migration Phase 13).

---

## R3 — Reproducible hub↔agent trust + declarative systems

**Decision**: Two mechanisms keep Beszel reproducible-from-git (FR-011, SC-009):

1. **Pinned keypair.** The hub↔agent link is authenticated by an ed25519 keypair. Agents receive
   the hub's **public** key via a non-secret variable (`BESZEL_KEY`, in `komodo/variables.toml`
   or forwarded env); the hub is given the **matching** identity so trust is stable across
   redeploy *and* a clean volume-wipe rebuild. Warm redeploys are covered by the persisted
   `beszel-data` volume; the pinned key is what covers a from-scratch rebuild. (Exact hub env for
   supplying the key is version-sensitive — validated at implement; the *decision* is "pin it,
   don't let first-run mint a throwaway".)
2. **Declarative systems.** The Dell and Mac systems are declared in a git-tracked
   `stacks/beszel/config.yml` (host, port, name, pinned key) that the hub **imports** on
   deploy — so the fleet list is reproduced from code, never hand-added in the UI. Shipped inline
   via Compose `configs:` (the same Komodo-safe pattern Homepage uses), so no host bind mount is
   needed.

**Fallback**: if `config.yml` import proves unreliable on the pinned hub version, a thin
**idempotent plane-3 play** (`stacks/beszel/configure/setup.yml`, PocketBase API GET-then-POST)
registers the two systems instead — same house pattern as `stacks/maintainerr/configure/`. A
failure surfaces loudly (visible play error), never silent drift.

**Hub admin**: the PocketBase superuser is provisioned **once** from a pinned credential
(`BESZEL_ADMIN_EMAIL` / `BESZEL_ADMIN_PASSWORD` via mise) — the "one-time credential
provisioning" SC-009 explicitly permits — not clicked through a first-run wizard on every
rebuild.

**Rationale**: keeps "clean rebuild → agents reproduced, re-deploy changes nothing" true without
manual UI steps.

**Alternatives considered**: UI "Add System" clicks (rejected — not reproducible); the newer
WebSocket **`TOKEN` + `HUB_URL`** agent mode (agent dials the hub) — viable, but the
hub-polls-agent SSH-key model gives the graceful Mac-down behaviour more directly and keeps the
agent env minimal; recorded as the alternative if NAT/port constraints ever appear.

---

## R4 — Tautulli ↔ Plex link (read-only) + reproducible setup

**Decision**: Tautulli connects to Plex using the **existing Plex server token** (`PLEX_TOKEN`)
against the Plex container over the shared `traefik` network (`http://plex:32400`), configured
for **read-only** monitoring — Tautulli never issues library/media mutations (FR-003, SC-002).

**Reproducible first-run (skip the wizard)**: Tautulli's setup is normally an interactive wizard
that mints an API key and stores the Plex connection in `config.ini`. To keep SC-009 (no manual
UI wiring beyond one-time credential provisioning), pre-seed the connection deterministically:

- **Primary**: seed a minimal `config.ini` (PMS host/port/token/identifier, a **deterministic**
  `TAUTULLI_API_KEY`, `first_run_complete = 1`) so the container starts already linked; a
  co-located **idempotent** `stacks/tautulli/configure/setup.yml` then *asserts* Plex is reachable
  read-only and history is accumulating (GET against the Tautulli API), failing loudly if not.
- **Fallback**: if seeding `config.ini` fights Tautulli's own rewrites on the pinned version, the
  plane-3 play instead drives Tautulli's HTTP API to register the Plex server post-first-run
  (GET-then-POST, idempotent) — same discipline as the Maintainerr/Seerr plays.

`PLEX_TOKEN` is **reused** from Phase 5 (Maintainerr already consumes it) — but it is currently
only in the live `.mise.toml`; this phase adds a proper **placeholder** to `.mise.toml.example`
so the token is codified, not implicit. The deterministic `TAUTULLI_API_KEY` (`openssl rand -hex
16`) is what the Homepage widget (R5) and the plane-3 assertion both read.

**Rationale**: read-only server-token is exactly how Tautulli is meant to observe Plex;
deterministic key + assert-play matches the established plane-3 pattern and keeps the wiring
re-runnable and drift-visible.

**Alternatives considered**: interactive wizard on every rebuild (rejected — not reproducible);
a full Plex OAuth flow (unnecessary — the server token already exists and is pinned).

---

## R5 — Front door: Homepage tiles + Tautulli widget

**Decision**: Edit the inline-config Homepage stack (`stacks/homepage/compose.yaml`) to add:

- a **Media** tile for **Tautulli** (`tautulli.ragnaforge.xyz`) wired to Homepage's **native
  `tautulli` widget**, showing live stream count / now-playing — the widget reads
  `TAUTULLI_API_KEY` via a `{{HOMEPAGE_VAR_TAUTULLI_KEY}}`-style env substitution (so the key is
  not hard-committed);
- an **Infrastructure** tile for **Beszel** (`beszel.ragnaforge.xyz`) as a **linked tile**.
  Homepage has **no native Beszel widget**, so Beszel is discoverable-and-linked; an optional
  `customapi` widget against the Beszel API can be added later if a summary stat is wanted (not
  required by SC-008, which asks for a widget "where the tool supports it").

The homepage stack therefore gains one forwarded secret (`TAUTULLI_API_KEY`) in its env.

**Rationale**: Homepage config is already shipped inline (Komodo-safe), so tiles + widget are a
git edit, not a new mechanism. SC-008 is met: both tools are TLS-fronted tiles, and the front
door shows a live now-playing summary via the Tautulli widget.

**Alternatives considered**: a bespoke dashboard page (rejected — Homepage is the front door);
faking a Beszel widget via screenshots (rejected — meaningless).

---

## R6 — The no-push boundary (dashboards only)

**Decision**: Configure Beszel **thresholds** (e.g. disk > 85%, sustained high CPU/RAM) so
breaches show as **visible red indicators** in the hub — but wire **no notification channel**
(no email, no webhook, no ntfy/shoutrrr). Tautulli likewise runs with **no** notification agents
configured. Net: **zero** push/alert egress from this phase (FR-014, SC-007).

**Rationale**: Both tools *can* push; the phase boundary is enforced by simply not configuring
any channel. This makes the Phase-9 line explicit and auditable (SC-007 is literally "0 pushes
emitted") rather than an accident of omission. When Phase 9 lands, it adds the ntfy channel on
top of the thresholds already defined here.

**Alternatives considered**: leaving thresholds unset until Phase 9 (rejected — the *visible*
indicator is a Phase-6 deliverable, US2 scenario 3); wiring ntfy now (rejected — out of scope,
FR-014).

---

## R7 — Storage, footprint & secret forwarding

**Decision**:
- **State → Dell.** `tautulli-config` (SQLite history) and `beszel-data` (PocketBase DB) are
  Dell-local named volumes; neither touches `/srv/nfs` (FR-016). The Mac agent has **no** volume.
- **Retention bounded** (FR-005): Tautulli history retention is set to a bounded window and
  Beszel metric retention to its configured record limit, so neither DB grows unbounded on the
  small disk. Values pinned in config, documented in the runbook.
- **Footprint** (FR-019/SC-010): Tautulli ~50–100 MB, hub ~50 MB, each agent ~15 MB — a few
  hundred MB total, well inside the Dell's remaining budget; verified *against the very metrics
  Beszel reports* in quickstart (the observers don't become the load problem).
- **Secret forwarding**: new/reused secrets — `PLEX_TOKEN`, `TAUTULLI_API_KEY`, `BESZEL_KEY`
  (public — may live in `variables.toml` instead), `BESZEL_ADMIN_EMAIL/PASSWORD` — are added to
  `komodo/bootstrap/periphery.compose.yaml` `environment:` and pushed with `make sync-secrets` +
  a Periphery recreate, per [[homeserve-ops-access]]. Compose references them as `${VAR}`.

**Rationale**: standard golden-rule placement and the established mise→Periphery secret path; no
new infrastructure.

**Alternatives considered**: putting stats DBs on NFS (rejected — golden rule, and SQLite over
NFS is fragile); unbounded retention (rejected — FR-005, small disk).

---

## Summary of decisions

| # | Decision |
|---|---|
| R1 | **Tautulli** (Dell) for Plex watch stats — now-playing + transcode breakdown + per-user history. |
| R2 | **Beszel** hub (Dell) + agents (Dell & Mac); hub **polls** agents → Mac-asleep = graceful down. |
| R3 | Reproducible trust via **pinned keypair** + **declarative `config.yml` systems** (plane-3 API fallback). |
| R4 | Tautulli→Plex **read-only** via reused `PLEX_TOKEN`; deterministic `TAUTULLI_API_KEY`; seed/assert, no wizard. |
| R5 | Homepage: native **Tautulli widget** + **Beszel linked tile** (edit inline configs). |
| R6 | **Thresholds set, no notification channel** → visible-only; 0 pushes (Phase-9 boundary). |
| R7 | State → Dell named volumes; bounded retention; secrets forwarded via mise→Periphery. |
