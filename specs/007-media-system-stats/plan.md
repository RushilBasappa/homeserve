# Implementation Plan: Phase 6 — Media & System Stats (Tautulli + Beszel)

**Branch**: `007-media-system-stats` | **Date**: 2026-07-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-media-system-stats/spec.md`

## Summary

Make the Phase-5 media pipeline and the two laptops it runs on **observable** — "see the
audience and the load" — by adding exactly two low-footprint tools and nothing else:

1. **Tautulli** (Dell) — Plex watch stats. Now-playing sessions with the **direct-play vs
   transcode** breakdown (the one number that predicts when the i3's iGPU/CPU falls over),
   plus per-user history. Connects to Plex **read-only** via the existing Plex server token;
   its SQLite history DB is a local named volume on the Dell (golden rule).
2. **Beszel** — host + container metrics. A **hub** on the Dell (web UI, PocketBase/SQLite
   store) plus a lightweight **agent** on the Dell and another on the Mac give **one fleet
   view**: CPU, RAM, disk %, network, temps, and per-container stats, with configurable
   thresholds shown as **visible indicators**.

Both UIs are fronted by the Phase-3 edge (`tautulli.ragnaforge.xyz`,
`beszel.ragnaforge.xyz`) and surfaced on Homepage — Tautulli via its native now-playing
widget, Beszel as a linked tile.

The design is disciplined by the same hard constraints as Phase 5, restated for this phase:

1. **Dashboards only — no push (spec FR-014).** Beszel *can* push (email/webhook/ntfy), so
   the boundary is enforced by **configuring thresholds but wiring no notification channel**:
   a breach is a red tile, never a phone buzz. Push wiring is Phase 9.
2. **Off-the-shelf, no bespoke scripts, no stale tools.** Tautulli and Beszel are both
   maintained, purpose-built tools. Fleet systems and the Plex link are reproduced from
   **pinned declarative config** (Beszel `config.yml` import; a co-located idempotent
   plane-3 play for the Tautulli↔Plex assertion), not hand-clicks.
3. **Stateful → Dell; the Mac runs only a stateless agent** (golden rule). Tautulli's history
   DB and Beszel's hub DB are Dell-local named volumes; the Mac holds no persistent state —
   only the Beszel agent, which the hub polls (so a sleeping Mac shows *down/stale*, never an
   error).

## Technical Context

**Language/Version**: No application language. Infrastructure-as-config: **Docker Compose**
stacks under `stacks/`, deployed by **Komodo** (declared in `komodo/stacks.toml`); any
plane-3 wiring is an **idempotent Ansible playbook** (`ansible.builtin.uri` against app REST
APIs) co-located at `stacks/<app>/configure/`. Secrets via **mise** (`.mise.toml`,
gitignored) forwarded to the Periphery env. Markdown runbook under `docs/runbooks/`.

**Primary Dependencies** (pinned to explicit image tags, never `:latest` — Diun/Phase-10 intent):
- **Media watch stats**: `ghcr.io/tautulli/tautulli` — Python; SQLite history DB; connects to
  Plex over HTTP(S) with a server token; native Homepage widget support.
- **Fleet metrics**: `henrygd/beszel` (hub — Go + embedded PocketBase, web UI on 8090) and
  `henrygd/beszel-agent` (agent — tiny Go binary; reads host metrics + `docker.sock` for
  per-container stats). One agent per monitored host (Dell + Mac).

**Storage**: All app **config/state** is on **local named volumes on the Dell**
(`tautulli-config`, `beszel-data`), never on `/srv/nfs` (CONVENTIONS "Data placement";
spec FR-016). Tautulli's SQLite history and Beszel's PocketBase DB both live in those volumes
and survive redeploy (FR-004, FR-011). Tautulli reads Plex over the API only — it touches **no**
media files. Neither tool mounts the `/srv/nfs` media tree.

**Testing**: Behavioural validation per `quickstart.md`, mapped to SC-001…SC-010 — including a
**transcode-visibility** check (SC-001: play a title that forces a transcode, confirm the
indicator), a **read-only assertion** (SC-002: zero Plex/media writes over an observation
window), a **history-persistence** check across redeploy (SC-003), a **both-nodes-one-view**
check (SC-004), a **threshold-indicator** check (SC-005), a **Mac-asleep graceful-down /
auto-recover** check (SC-006), a **no-push** audit (SC-007), and an **idempotent-rebuild**
check (SC-009).

**Target Platform**: `ragnaforge-dell` (10.0.0.70) — Tautulli, the Beszel **hub**, and the
Dell **agent** (all stateful state lives here). `ragnaforge-mac` (10.0.0.71) — the stateless
Beszel **agent** only (no web UI to route, so the Traefik-can't-route-Mac constraint
[[homeserve-traefik-mac-routing]] does not apply; only the Dell hub UI is fronted). LAN
`10.0.0.0/24`; both node IPs are existing Komodo variables (`DELL_LAN_IP`, `MAC_LAN_IP`).

**Project Type**: Infrastructure/documentation monorepo. Changes land in new `stacks/*/`
directories, `komodo/stacks.toml` (+ `komodo/variables.toml` if any non-secret constants),
`stacks/homepage/compose.yaml` (add two tiles + the Tautulli widget), `.mise.toml.example`
(new placeholders), `komodo/bootstrap/periphery.compose.yaml` (forward the new secrets),
`docs/CONVENTIONS.md` (ports/URLs tables), and a new `docs/runbooks/phase6-stats.md`.

**Performance Goals**: The tools must be *observers, not load* (spec FR-019/SC-010). Tautulli
(~50–100 MB) and the Beszel hub + agents (~50 MB hub, ~15 MB per agent) sit comfortably in the
Dell's remaining budget alongside the Phase-5 stack; the Mac carries only the tiny agent.

**Constraints**:
- **Dashboards only** — thresholds and now-playing are **visible indicators**; **zero** push
  channels are configured (FR-014, SC-007). This is the headline boundary of the phase.
- **Read-only Plex** — Tautulli never mutates the Plex library, metadata, or on-disk media
  (FR-003, SC-002).
- **Golden rule** — stateful DBs on the Dell; the Mac runs only the stateless agent (FR-016).
- **Graceful Mac degradation** — a sleeping/off Mac must render as *down/stale*, not an error,
  and auto-recover (FR-010, SC-006). The hub-polls-agent model gives this for free.
- **Lightweight only** — no SMART/Scrutiny, no Uptime Kuma, no Prometheus/Grafana (FR-015).
- **No bespoke scripts / three-plane separation** — as Phase 5.

**Scale/Scope**: One household. Two new UIs, two hosts monitored, ~4 new containers
(Tautulli, Beszel hub, Dell agent, Mac agent). Plex-only watch stats (Jellyfin analytics are an
accepted gap — Jellystat was dropped).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an **unfilled template** — no
ratified principles, so there are no formal gates. The project's *de facto* principles from
`PLAN.md` / `CONVENTIONS.md` are upheld:

- **Stateful → Dell**: Tautulli DB + Beszel hub DB are Dell-local named volumes; the Mac runs
  only the stateless agent. ✅
- **Off-the-shelf, minimal custom code**: both tools are maintained and purpose-built; fleet
  systems come from Beszel's declarative `config.yml`; the only custom code is a thin,
  idempotent plane-3 assertion play for the Tautulli↔Plex link. ✅
- **Reproducible from git**: stacks in `stacks/`, declared in `komodo/stacks.toml`; Beszel
  systems + pinned key in git; secrets in `mise`. A clean rebuild reproduces the whole phase. ✅
- **No secrets in the repo**: new secrets are placeholders in `.mise.toml.example`, referenced
  as `${VAR}`; the reused `PLEX_TOKEN` gets a proper placeholder (it was previously only in the
  live `.mise.toml`). ✅
- **Three configuration planes separated** (spec FR-018): `provision/` untouched; any wiring is
  co-located with its stack, post-deploy, idempotent. ✅
- **Dashboards-only boundary** (spec FR-014): thresholds set, **no** notification channel wired
  — the Phase-9 line is explicit, not accidental. ✅

**Result: PASS.** No unjustified complexity. One honest, bounded caveat is recorded in
Complexity Tracking (from-scratch key reproducibility).

## Project Structure

### Documentation (this feature)

```text
specs/007-media-system-stats/
├── plan.md              # This file
├── research.md          # Phase 0 — the technical decisions + rationale (Tautulli seeding, Beszel key/systems, no-push, widgets)
├── data-model.md        # Phase 1 — entities (Stream session, Watch-history record, Node, Container metric, Threshold, Beszel System, Pinned key)
├── quickstart.md        # Phase 1 — validation runbook (SC-001…SC-010)
├── contracts/
│   ├── stack-inventory.md    # stacks × node × ports × volumes × secrets
│   └── wiring.md             # plane-3 / declarative connection contract (Tautulli→Plex; hub↔agents; Homepage→Tautulli)
├── checklists/
│   └── requirements.md       # Spec quality checklist (from /speckit-specify) — all pass
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
stacks/
├── tautulli/
│   ├── compose.yaml            # Dell — Plex watch stats; tautulli-config volume; Traefik labels (port 8181)
│   └── configure/
│       └── setup.yml           #   PLANE 3 — idempotent: assert Plex reachable read-only via PLEX_TOKEN; confirm history DB persists
└── beszel/
    ├── compose.yaml            # Dell — hub ONLY (UI 8090); beszel-data volume; Traefik labels
    ├── agent.compose.yaml      # GENERIC node-agnostic agent — ONE file for every node (Dell, Mac, future)
    └── config.yml              #   DECLARATIVE systems (one line per node) imported by the hub (no manual "Add System")

komodo/
├── stacks.toml                 # EDIT — `tautulli`, `beszel` (hub), and one `beszel-agent-<node>` per node (Dell+Mac) sharing agent.compose.yaml; manual deploys
└── variables.toml              # (unchanged — non-secret node values are inlined literals; Komodo does not interpolate [[VAR]] into git compose)

komodo/bootstrap/
└── periphery.compose.yaml      # EDIT — forward the new secrets to the Periphery env (PLEX_TOKEN, TAUTULLI_API_KEY, Beszel key/admin)

stacks/homepage/compose.yaml    # EDIT — add Tautulli + Beszel tiles; add the native Tautulli now-playing widget (inline configs)

docs/
├── CONVENTIONS.md              # EDIT — grow the ports/URL tables (tautulli, beszel)
└── runbooks/
    └── phase6-stats.md         # NEW — bring-up order, Plex-link check, threshold drill, Mac-asleep drill, no-push audit

.mise.toml.example              # EDIT — new placeholders (PLEX_TOKEN, TAUTULLI_API_KEY, BESZEL_KEY, hub admin creds)
```

**Structure Decision**: **One stack per tool** (`stacks/tautulli/`, `stacks/beszel/`), plus a
**single generic, node-agnostic agent** (`stacks/beszel/agent.compose.yaml`). The Beszel **hub**
is its own single-purpose stack; every node's **agent** — the Dell's included — is that one
generic file, deployed as a `beszel-agent-<node>` Komodo stack (same `file_paths`, different
`server`). This is deliberate: an agent is identical on every host, so **scaling to N nodes is N
`[[stack]]` declarations, not N files** — directly serving the code-reproducible/portability goal.
Beszel's fleet **systems** are declared in a git-tracked `config.yml` imported by the hub, so
adding a node is one `config.yml` line + one stack block, reproducible-from-code, no UI click
(FR-011, SC-009). Tautulli keeps a `configure/` plane-3 play mirroring the Phase-5 house style
(`stacks/*/configure/setup.yml`).

## Complexity Tracking

| Caveat (not a violation) | Why it exists | How it is bounded |
|---|---|---|
| **From-scratch key reproducibility** | The hub↔agent trust is an ed25519 keypair. On redeploy it survives via the persisted Dell `beszel-data` volume; on a *wiped-volume* rebuild a freshly generated hub key would not match the agents' pinned `KEY`. | Pin the keypair: agents consume the hub **public** key from a non-secret var (`BESZEL_KEY`); the hub is given the matching key so a clean rebuild reproduces the same identity (exact env validated at implement — research R3). This keeps SC-009 (redeploy changes nothing) true even across a volume wipe, not just a warm redeploy. |

*(An earlier draft carried a "Mac agent runs on macOS/Docker-Desktop → reduced host-metric
fidelity" caveat. Removed as incorrect: `ragnaforge-mac` runs **Debian Linux**, so the Mac agent
has full host-metric fidelity like the Dell — no VM layer, no macOS limitation.)*
