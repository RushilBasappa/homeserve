# Implementation Plan: Phase 2 — Orchestration (Komodo)

**Branch**: `003-komodo-orchestration` | **Date**: 2026-07-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-komodo-orchestration/spec.md`

## Summary

Turn the two Phase-1 Docker hosts into a **centrally managed fleet** with
**Komodo** (v2):

1. **Komodo Core** — a Docker Compose stack on the Dell (`komodo-core:2` +
   MongoDB), the web UI/API and single deploy surface, its state persisted on the
   Dell.
2. **Komodo Periphery** — a pinned agent container on **each** node that runs
   `docker compose` locally; Core connects inbound on port 8120 (PKI auth).
3. **Git as source of truth** — the fleet's Servers and Stacks are declared in
   **TOML** under `komodo/`, and Komodo **ResourceSync** reconciles from this repo;
   each Stack maps to a `stacks/<app>/compose.yaml` and a target node.
4. **Secrets from `mise`** — Core's own secrets and stack `${VAR}` references are
   injected from the gitignored `.mise.toml`; no real value in any tracked file.
5. **Deliberate deploys** — manual-trigger by default, optional per-stack webhook.

Correctness is proven behaviorally by deploying a trivial **`whoami`** test stack
to each node from Core alone, syncing a change from git, injecting a secret with
no value in git, killing/restarting to prove independence and persistence, and a
`grep` confirming the tree stays secret-free. **No real application services are
deployed** — those are Phases 3–6.

## Technical Context

**Language/Version**: No application language. Infrastructure-as-config: **Docker
Compose** (`compose.yaml`) for the bootstrap + stacks, and **Komodo TOML**
resource definitions. Komodo **v2** (`ghcr.io/moghtech/komodo-*:2`). `mise`
renders secrets into the environment.

**Primary Dependencies**: Komodo **Core** + **Periphery** (v2); **MongoDB**
(Core's datastore, cache-capped); Docker Engine + compose plugin (Phase 1);
`mise` for secret injection. All images pinned to a visible major (`:2`), not
`:latest`.

**Storage**: Core's **MongoDB** in a named volume **on the Dell** (stateful →
Dell). No shared/NFS storage in this phase; the test stack is stateless.

**Testing**: No unit suite. Verification is behavioral (see `quickstart.md`):
deploy the `whoami` stack to a chosen node from Core; sync a git change; inject a
secret via `${VAR}` with no value tracked; deploy to one node while the other is
offline; restart the Dell and confirm Core state persists; `grep` proving the tree
is secret-free.

**Target Platform**: The two Phase-1 Debian (trixie) Docker hosts —
`ragnaforge-dell` (10.0.0.70, Core + Periphery + MongoDB) and `ragnaforge-mac`
(10.0.0.71, Periphery only) — on LAN `10.0.0.0/24`, also reachable over Tailscale.

**Project Type**: Infrastructure/documentation monorepo. Komodo resource
definitions in `komodo/`; bootstrap + stacks in `stacks/` (and
`komodo/bootstrap/`); entry points wrap `mise exec -- docker compose`.

**Performance Goals**: N/A. Practical: Core + MongoDB fit comfortably in the
Dell's 7.5 GB alongside future stacks (MongoDB WiredTiger cache capped ~0.5 GB); a
stack deploy from the UI completes in seconds over LAN.

**Constraints**: **RAM-lean** on 7.5 GB nodes (single-container MongoDB, capped
cache). **Secret-free tree** — real secrets only in the gitignored `.mise.toml`
(FR-006). **Git is the source of truth** for servers/stacks (FR-003). **Manual
deploy by default** (FR-007). Core **never publicly exposed** — LAN/Tailscale only
(FR-009); TLS/domain deferred to Phase 3. Each node **independently manageable**
(FR-010). **Stateful → Dell** (Core's DB).

**Scale/Scope**: 2 nodes; 1 Core; 2 Periphery agents; 1 MongoDB; a handful of
TOML resource files; 1 trivial test stack. Grows as later phases add stacks under
the same `komodo/` + `stacks/` model.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an unpopulated
template — no ratified principles, so there are no constitution gates to evaluate.
Applied instead as the master plan's north stars:

- **Minimal custom code / off-the-shelf tools** — Komodo + official images +
  Compose; no bespoke orchestration. ✅
- **Nothing silently outdated** — images pinned to a visible major (`:2`), updated
  deliberately via Komodo redeploy (Phase 10), not blind `:latest`. ✅
- **Reproducible by a competent friend** — bootstrap compose + git-declared
  resource TOML + documented steps; one deploy surface. ✅
- **Secrets never leak** — real values only in the gitignored `.mise.toml`; the
  git-synced TOML/compose carry references, never values. ✅

**Result**: PASS. **Post-design re-check**: PASS — design keeps the tree
secret-free, confines state to the Dell, and adds no bespoke code; the one open
risk (Periphery env forwarding for `${VAR}` secrets) has a documented fallback
(Komodo secret Variables), so it does not block the design.

## Project Structure

### Documentation (this feature)

```text
specs/003-komodo-orchestration/
├── plan.md              # This file (/speckit-plan output)
├── spec.md              # Feature specification
├── research.md          # Phase 0 output — decisions & rationale
├── data-model.md        # Phase 1 output — entities & required content
├── quickstart.md        # Phase 1 output — validation scenarios
├── contracts/           # Phase 1 output
│   ├── orchestration-contract.md   # "managed fleet" interface + postconditions
│   └── resource-sync-contract.md   # required git-declared resources + secret-free rule
├── checklists/
│   └── requirements.md  # Spec quality checklist (passing)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
homeserve/
├── komodo/                          # Komodo resource definitions (dir + README from Phase 0)
│   ├── README.md                    # exists
│   ├── servers.toml                 # NEW: [[server]] dell + mac (address :8120)
│   ├── stacks.toml                  # NEW: [[stack]] whoami → target server → stacks/whoami
│   ├── variables.toml               # NEW: non-secret vars only (never secret values)
│   └── bootstrap/                   # NEW: out-of-band bring-up of the control plane
│       ├── core.compose.yaml        #   komodo-core:2 + mongo (Dell); state on Dell
│       ├── core.env.example         #   non-secret Core config (real secrets via mise)
│       └── periphery.compose.yaml   #   komodo-periphery:2 (both nodes; docker.sock)
├── stacks/                          # Compose stacks (dir + README from Phase 0)
│   └── whoami/                      # NEW: trivial stateless test stack (traefik/whoami)
│       └── compose.yaml
├── Makefile                         # extended: komodo bootstrap + sync helper targets
├── .mise.toml.example               # extended: KOMODO_DB_PASSWORD, _WEBHOOK_SECRET, _JWT_SECRET
└── docs/
    └── runbooks/
        └── phase2-komodo.md         # NEW: bootstrap + connect + sync + deploy runbook
```

**Structure Decision**: Reuse the Phase-0 `komodo/` and `stacks/` directories.
Komodo Core and the two Periphery agents are **bootstrapped out-of-band** from
pinned compose files under `komodo/bootstrap/` (Core on the Dell, Periphery on
each node) because they *are* the orchestrator — they can't be deployed by an
orchestrator that isn't up yet. Everything above the control plane (the `whoami`
test stack, and every later app) is **Komodo-managed**, declared as TOML resources
in `komodo/` that ResourceSync reconciles from this git repo. Secrets come from
the gitignored `.mise.toml` via `mise exec`; the tracked TOML/compose reference
`${VAR}` / `[[VAR]]`, never values. New `make` targets wrap the bootstrap and sync;
a runbook documents the one-time bring-up.

## Complexity Tracking

No constitution violations. This section intentionally left empty.
