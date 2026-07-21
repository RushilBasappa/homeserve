# Implementation Plan: Phase 7a — Apps: Finance & Secrets (Actual + Vaultwarden + Sure)

**Branch**: `008-finance-secrets-apps` | **Date**: 2026-07-21 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-finance-secrets-apps/spec.md`

## Summary

Bring the first **personal-data apps** onto the lab — the ones that hold the household's money
and passwords — as three isolated, single-purpose stacks, each following the established house
pattern (Compose under `stacks/<app>/`, Traefik labels → `https://<app>.ragnaforge.xyz`, a
Homepage tile, a Dell-local config volume, secrets from `mise`). Nothing new is invented; this is
the Phase-3/5 recipe applied to three off-the-shelf apps:

1. **Vaultwarden** (`stacks/vaultwarden/`, Dell) — the Rust Bitwarden-compatible password server.
   Single container, `vaultwarden-data` volume (SQLite `db.sqlite3` + attachments + RSA JWT keys).
   The vault is **end-to-end encrypted** — the server stores only ciphertext, the master password
   never reaches it. This is the phase's **P1/MVP** and its most safety-critical app: preserving
   an **existing** vault through the migration and locking down registration (`SIGNUPS_ALLOWED=false`,
   Argon2-hashed `ADMIN_TOKEN`) are the headline requirements.
2. **Actual Budget** (`stacks/actual/`, Dell) — the local-first budgeting server. Single container,
   `actual-data` volume (`server-files/account.sqlite` + `user-files/` budgets). Runs plain HTTP
   behind Traefik (no `ACTUAL_HTTPS_*` set); an existing budget is preserved by restoring `/data`.
3. **Sure** (`stacks/sure/`, Dell) — the community fork of Maybe Finance (`we-promise/sure`,
   AGPLv3) for net-worth / wealth tracking. **Multi-container**: `web` (Rails/Puma :3000) + `worker`
   (Sidekiq) + `db` (PostgreSQL 16) + `redis`. All state on the Dell (`sure-pgdata`, `sure-storage`).
   The `web` entrypoint runs `rails db:prepare` on boot, and both app services `depends_on` healthy
   `db`+`redis`, so a cold deploy self-migrates and comes up healthy with no manual step.

**Actual and Sure run side by side on purpose** (the finance-tool trial); the three stacks are
fully isolated (own dirs, containers, volumes, networks) so the loser can be dropped with a single
stack removal. **Choosing** the winner is out of scope.

The design honours the same hard constraints as the earlier phases, restated for this phase:

1. **LAN/VPN-only, never public (FR-015).** All three ride the Phase-3 edge at `*.ragnaforge.xyz`,
   which resolves internally (AdGuard → the Dell) and is **not** router-forwarded. A password
   server on the public internet would be a critical failure; the boundary is enforced by adding
   **no** port-forward and publishing **no** host ports.
2. **Stateful → Dell; nothing on the Mac, nothing on `/srv/nfs` (FR-017).** Every volume is a
   Dell-local named volume: the vault store, the budget data, and Sure's PostgreSQL/Redis/storage.
3. **Secrets from `mise`, never committed (FR-016).** Only three secrets are container-referenced —
   `VAULTWARDEN_ADMIN_TOKEN`, `SURE_SECRET_KEY_BASE`, `SURE_POSTGRES_PASSWORD` — forwarded to the
   Periphery env and read as `${VAR}`. Actual needs **no** container secret (its login password is
   set in-app on first run). Non-secret config (hostnames, `DOMAIN`, `RAILS_ASSUME_SSL`) is inlined
   as literals, since Komodo does not interpolate `[[VAR]]` into git-pulled compose.

## Technical Context

**Language/Version**: No application code authored. Infrastructure-as-config: **Docker Compose**
stacks under `stacks/`, deployed by **Komodo** (declared in `komodo/stacks.toml`). Any optional
post-deploy assertion is an **idempotent Ansible play** co-located at `stacks/<app>/configure/`
(the Phase-5/6 house style). Secrets via **mise** (`.mise.toml`, gitignored) forwarded to the
Periphery env. A new runbook lands at `docs/runbooks/phase7a-finance-secrets.md`.

**Primary Dependencies** (pinned to explicit tags where a stable tag exists — Diun/Phase-10 intent;
verify current tags at deploy):
- **Vaultwarden**: `vaultwarden/server:1.36.0-alpine` — HTTP on **:80** in Docker; data folder `/data`;
  websockets folded into the main port (old **3012 is removed** — do not publish it; Traefik
  forwards the `Upgrade` header automatically); liveness at `/alive`.
- **Actual**: `actualbudget/actual-server:26.7.0-alpine` — HTTP on **:5006**; data folder `/data`
  (`server-files/`, `user-files/`); plain HTTP behind the proxy (leave `ACTUAL_HTTPS_*` unset).
- **Sure**: `ghcr.io/we-promise/sure:stable` (`web` + `worker`), `postgres:16` (`db`),
  `redis:7-alpine` (`redis`) — web on **:3000**; Rails health at `/up`; `SELF_HOSTED=true`,
  `RAILS_ASSUME_SSL=true` (TLS terminated at Traefik). Sure publishes only a rolling `:stable` tag
  on GHCR (semver releases exist to v0.7.2 but matching GHCR image tags are unconfirmed) — a
  **deliberate exception** to the pin-explicit-tags rule, handled like `seerr` (pin the
  `stable@sha256:…` digest for reproducibility; Diun watches). See Complexity Tracking.

**Storage**: All app config/state on **Dell-local named volumes**, never on `/srv/nfs`
(CONVENTIONS golden rule; spec FR-017): `vaultwarden-data`, `actual-data`, `sure-pgdata`
(`/var/lib/postgresql/data`), `sure-storage` (`/rails/storage`, ActiveStorage, shared by web+worker),
and `sure-redis` (`/data`, optional — Sidekiq queue only). Vault + budget survive redeploy (FR-002,
FR-004, FR-006, FR-007); Sure's Postgres survives redeploy without re-registration (FR-011).

**Testing**: Behavioural validation per `quickstart.md`, mapped to SC-001…SC-009 — vault
preservation + unlock (SC-001), signup-closed / admin-gated (SC-002), budget preservation + edit
survives restart (SC-003), Sure cold-deploy healthy + data survives redeploy (SC-004), TLS + Homepage
tiles (SC-005), **no public exposure** audit (SC-006), **no committed secrets** audit (SC-007),
idempotent rebuild with all state on the Dell (SC-008), and **stack-isolation** (remove one, others
live — SC-009).

**Target Platform**: `ragnaforge-dell` (10.0.0.70) — **all three stacks** and all their state
(these are stateful personal-data apps → golden rule). **Nothing on `ragnaforge-mac`**, so the
Traefik-can't-route-Mac constraint ([[homeserve-traefik-mac-routing]]) does not arise. LAN
`10.0.0.0/24`; existing Komodo variables `DELL_LAN_IP` / `FLEET_DOMAIN` cover host/domain.

**Project Type**: Infrastructure/documentation monorepo. Changes land in three new `stacks/*/`
directories, `komodo/stacks.toml` (+3 `[[stack]]` blocks), `stacks/homepage/compose.yaml` (+3 tiles),
`.mise.toml.example` (+3 placeholders), `komodo/bootstrap/periphery.compose.yaml` (forward the 3 new
container secrets), `docs/CONVENTIONS.md` (URL/port tables), and a new
`docs/runbooks/phase7a-finance-secrets.md`.

**Performance Goals / Footprint**: Vaultwarden (~20–50 MB) and Actual (~100–150 MB) are tiny. **Sure
is the heavy component** — a Rails app + Sidekiq worker + PostgreSQL + Redis (~roughly 500 MB–1 GB
combined) on a 7.5 GB Dell already carrying the Phase-5 media stack. This is the phase's real budget
pressure and a reason Sure is the natural retire-candidate if the trial favours Actual (see
Complexity Tracking). Footprint is observed via the Phase-6 Beszel fleet view.

**Constraints**:
- **LAN/VPN-only, never public** — no router-forward, no host ports for any of the three (FR-015, SC-006).
- **Secrets from `mise`, never committed** — only the 3 container secrets are forwarded; Actual needs none (FR-016, SC-007).
- **Golden rule** — every volume on the Dell; nothing on the Mac or `/srv/nfs` (FR-017, SC-008).
- **Registration lockdown** — Vaultwarden `SIGNUPS_ALLOWED=false` after initial account(s); `/admin` gated by an Argon2-hashed token (FR-003, SC-002).
- **Cold-deploy self-migrates** — Sure's `web` runs `db:prepare` on boot and waits on healthy `db`+`redis`; no manual migration step (FR-010, SC-004).
- **Isolated stacks** — three separate stacks/volumes so the trial loser drops cleanly (FR-014, SC-009).
- **One-time data preservation only** — scheduled/offsite backups are Phase 10 (FR-019).

**Scale/Scope**: One household. Three new UIs, one node (Dell), ~6 new containers (vaultwarden;
actual; sure web+worker+db+redis). No inter-app wiring — each stack is standalone (unlike the
Phase-5 servarr mesh); the only intra-stack coupling is Sure's web/worker→db/redis dependency.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an **unfilled template** — no
ratified principles, so there are no formal gates. The project's *de facto* principles from
`PLAN.md` / `CONVENTIONS.md` are upheld:

- **Stateful → Dell**: all three stacks and every volume are Dell-local; nothing on the Mac or
  `/srv/nfs`. ✅
- **Off-the-shelf, minimal custom code**: Vaultwarden, Actual, and Sure are maintained, purpose-built
  apps run from their own images; there is **no** custom application code and **no** inter-app wiring
  to script — the only optional custom artifact is a thin idempotent assert play per app. ✅
- **Reproducible from git**: three stacks in `stacks/`, declared in `komodo/stacks.toml`; secrets in
  `mise`; a clean rebuild reproduces the whole phase (subject to the one-time data restore and the
  Sure rolling-tag caveat below). ✅
- **No secrets in the repo**: the 3 new secrets are placeholders in `.mise.toml.example`, referenced
  as `${VAR}`; Actual adds none. ✅
- **LAN/VPN-only edge**: no router-forward, no published host ports; the same Phase-3 Traefik +
  wildcard-TLS front door, nothing public. ✅
- **Isolated stacks**: three separate directories/containers/volumes — dropping one (the trial loser)
  leaves the others untouched. ✅

**Result: PASS.** No unjustified complexity. Two honest, bounded caveats are recorded in Complexity
Tracking (Sure's rolling image tag; Sure's multi-container RAM footprint).

## Project Structure

### Documentation (this feature)

```text
specs/008-finance-secrets-apps/
├── plan.md              # This file
├── research.md          # Phase 0 — per-app decisions + rationale (images, ports, env, data-import, lockdown)
├── data-model.md        # Phase 1 — entities (Password vault, Budget, Financial account/Net-worth, Config volume, Secret)
├── quickstart.md        # Phase 1 — validation runbook (SC-001…SC-009)
├── contracts/
│   ├── stack-inventory.md    # stacks × node × ports × volumes × secrets
│   └── wiring.md             # intra-stack deps (Sure), data-preservation restore, optional plane-3 asserts, the no-public-exposure invariant
├── checklists/
│   └── requirements.md       # Spec quality checklist (from /speckit-specify) — all pass
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
stacks/
├── vaultwarden/
│   ├── compose.yaml            # Dell — password server; vaultwarden-data volume; Traefik labels (port 80)
│   └── configure/
│       └── setup.yml           #   PLANE 3 (optional, idempotent) — assert /alive up + signups CLOSED; never mutates the vault
├── actual/
│   └── compose.yaml            # Dell — budgeting; actual-data volume; Traefik labels (port 5006); plain HTTP behind proxy
└── sure/
    └── compose.yaml            # Dell — web + worker + db(postgres:16) + redis; sure-pgdata/sure-storage/sure-redis; Traefik on web (port 3000)

komodo/
└── stacks.toml                 # EDIT — +3 `[[stack]]` (vaultwarden, actual, sure), server=ragnaforge-dell, webhook_enabled=false

komodo/bootstrap/
└── periphery.compose.yaml      # EDIT — forward the 3 container secrets (VAULTWARDEN_ADMIN_TOKEN, SURE_SECRET_KEY_BASE, SURE_POSTGRES_PASSWORD)

stacks/homepage/compose.yaml    # EDIT — add Vaultwarden + Actual + Sure tiles (Apps group); no native widgets needed

docs/
├── CONVENTIONS.md              # EDIT — grow the URL/port tables (vaultwarden, actual, sure)
└── runbooks/
    └── phase7a-finance-secrets.md   # NEW — bring-up order, one-time data restore (vault + budget), Sure cold-deploy, lockdown + no-public audit

.mise.toml.example              # EDIT — +3 placeholders (VAULTWARDEN_ADMIN_TOKEN, SURE_SECRET_KEY_BASE, SURE_POSTGRES_PASSWORD)
```

**Structure Decision**: **One stack per app** (`stacks/vaultwarden/`, `stacks/actual/`, `stacks/sure/`),
each a self-contained directory with its own compose, volumes, and (for Sure) internal network — so
the three are provably isolated and the Actual-vs-Sure trial loser is a one-stack removal (FR-014,
SC-009). Vaultwarden and Actual are single-container; **Sure is one compose with four services**
(web/worker/db/redis) on an internal `sure` network plus the shared external `traefik` network for
`web`'s route only — mirroring the Phase-5 `arr` stack's "multi-service pipeline as one deployable
unit" pattern. A per-app `configure/` assert play is included only where it earns its keep
(Vaultwarden's security-critical signup-closed check); Actual and Sure health are validated by the
quickstart rather than a bespoke play, keeping custom code minimal.

## Complexity Tracking

| Caveat (not a violation) | Why it exists | How it is bounded |
|---|---|---|
| **Sure ships only a rolling `:stable` tag** | `we-promise/sure`'s published compose uses `ghcr.io/we-promise/sure:stable`; GitHub releases exist (to v0.7.2) but matching **semver GHCR image tags are unconfirmed**, so there is no verified `vX.Y.Z` tag to pin. | Treat exactly like `seerr` (documented rolling-tag exception): pin `stable@sha256:<digest>` in the compose for reproducibility, record the digest, and let **Diun** (Phase 10) surface updates. Deliberate, isolated to one service, documented in the stack header. |
| **Sure is multi-container (web+worker+db+redis) → the heaviest 7a component** | Net-worth tracking in Sure is a Rails app that inherently needs PostgreSQL + Redis + a Sidekiq worker; ~500 MB–1 GB combined on a 7.5 GB Dell already running the Phase-5 stack. | This is the app's inherent architecture, not accidental complexity. Footprint is observed via the Phase-6 Beszel view; **Sure is the natural retire-candidate** if the Actual-vs-Sure trial favours the far-lighter Actual (the spec's isolation requirement makes that a clean one-stack removal). If RAM-pressured before the trial concludes, Sure is deployed last and can be stopped without touching the P1 apps. |
