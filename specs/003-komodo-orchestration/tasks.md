---
description: "Task list for Phase 2 — Orchestration (Komodo)"
---

# Tasks: Phase 2 — Orchestration (Komodo)

**Input**: Design documents from `/specs/003-komodo-orchestration/`

**Prerequisites**: plan.md (required), spec.md (required), research.md,
data-model.md, contracts/, quickstart.md

**Tests**: No automated test suite is requested — this phase produces
orchestration config (bootstrap compose + Komodo TOML) and a runbook.
Verification is by the scriptable conformance checks in `contracts/` and the
scenarios in `quickstart.md` (grouped in the Polish phase). Full behavioral checks
require the two real hosts and a running Komodo Core.

**Organization**: Tasks are grouped by user story so each can be implemented and
verified independently.

## Implementation status (2026-07-19)

All **authorable artifacts** are complete and locally verified: the bootstrap
compose files, `make` targets, git-declared resources (`servers.toml`,
`stacks.toml`, `variables.toml`), the `whoami` test stack, the secret
placeholders, the runbook, and the README entry. Syntax (YAML/TOML) validates and
the secret-free / resource-declaration grep checks pass (T018 + the scriptable
part of T022).

The remaining tasks are **⏸ BLOCKED — live bring-up**: they require the two real
nodes (`ragnaforge-dell`, `ragnaforge-mac`) plus a running Komodo Core and cannot
be executed from the authoring environment. Follow
[`docs/runbooks/phase2-komodo.md`](../../docs/runbooks/phase2-komodo.md) to run
them on the hosts. Blocked: **T007, T009, T012, T014, T016, T017, T019, T020,
T023**, and the host-dependent portion of **T022** (Core reachability, agent
health, on-target-node placement — the grep-based conformance checks already
pass).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- All paths are relative to the repository root (`/Users/rushilbasappa/Workspace/projects/homeserve`)

## Path Conventions

Infrastructure/documentation monorepo. Komodo resource definitions live in
`komodo/` (TOML) with out-of-band bring-up under `komodo/bootstrap/`; deployable
stacks in `stacks/<app>/`; the one-time runbook in `docs/runbooks/`; entry points
extend the root `Makefile`. No `src/`/`tests/` tree.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directory skeleton and secret placeholders the bootstrap
and resources fill in.

- [X] T001 Create the Phase-2 directory skeleton: `komodo/bootstrap/` and `stacks/whoami/` (e.g. `mkdir -p komodo/bootstrap stacks/whoami`)
- [X] T002 [P] Add Komodo secret placeholders to `.mise.toml.example`: `KOMODO_DB_PASSWORD`, `KOMODO_WEBHOOK_SECRET`, `KOMODO_JWT_SECRET` (research R4, R9)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Bring up the control plane (Core + both Periphery agents) and
register the servers from git. Nothing can be deployed or declared until this
exists.

**⚠️ CRITICAL**: No user story can be completed until this phase is done.

- [X] T003 Create `komodo/bootstrap/core.compose.yaml`: `ghcr.io/moghtech/komodo-core:2` + `mongo` (cap `--wiredTigerCacheSizeGB=0.5`), Mongo data in a **named volume on the Dell**, Core UI/API on `9120` bound to LAN/Tailscale only, secrets from the env (`mise`) — not literals (research R1, R7, R9; data-model "Control Plane")
- [X] T004 [P] Create `komodo/bootstrap/core.env.example`: **non-secret** Core config (host/base URL, DB name, disable-registration toggle); real secrets come from `.mise.toml` via `mise`, never this file (research R7)
- [X] T005 [P] Create `komodo/bootstrap/periphery.compose.yaml`: `ghcr.io/moghtech/komodo-periphery:2`, mount `/var/run/docker.sock`, expose `8120`, mount working dirs for the pulled repo/stacks (research R2, R3; data-model "Node Agent")
- [X] T006 Extend the root `Makefile` with `komodo-core` (bring up Core on the Dell via `mise exec -- docker compose ...`) and `komodo-periphery` (bring up the agent on a node) targets (research R3; contracts/orchestration-contract.md) — depends on T003, T005
- [ ] T007 Bootstrap the control plane: run `make komodo-core` on the Dell and `make komodo-periphery` on **each** node; create the single admin user in Core and **disable open registration** (research R3, R7; FR-001, FR-009) — depends on T006
- [X] T008 [P] Create `komodo/servers.toml`: `[[server]]` for `ragnaforge-dell` (`http://10.0.0.70:8120`) and `ragnaforge-mac` (`http://10.0.0.71:8120`), `enabled = true` (research R5; data-model "Server"; FR-002, FR-003)
- [ ] T009 Configure a Komodo **ResourceSync** in Core pointing at this git repo's `komodo/` TOML, run the initial sync, and confirm **both** servers register and report **healthy** (research R5; FR-002, FR-003; quickstart 2–3) — depends on T007, T008

**Checkpoint**: Control plane up, both agents healthy, fleet git-synced.

---

## Phase 3: User Story 1 - Deploy a stack to either node from one place (Priority: P1) 🎯 MVP

**Goal**: Deploy a Compose stack to a chosen node from Core alone — no SSH, no
manual `docker compose` on the node.

**Independent Test**: From the Core UI/CLI, deploy the `whoami` stack targeting one
node; confirm its container runs on that node (and not the other) and its status +
logs are visible centrally.

### Implementation for User Story 1

- [X] T010 [P] [US1] Create `stacks/whoami/compose.yaml`: a trivial **stateless** `traefik/whoami` service (no host ports, no volumes, no state), per the naming conventions (research R8; docs/CONVENTIONS.md)
- [X] T011 [US1] Declare the stack in `komodo/stacks.toml`: `[[stack]]` name `whoami`, `stack.config.server` targeting a node, `file_paths = ["stacks/whoami/compose.yaml"]`, repo = this repo (research R5; data-model "Stack"; FR-004) — needs registered servers (T009)
- [ ] T012 [US1] Sync + deploy `whoami` to the chosen node from Core; verify it runs on **that** node and NOT the other, and its status + logs are visible centrally (FR-004, FR-005; SC-001; quickstart 4) — depends on T010, T011

**Checkpoint**: A stack deploys to a chosen node from Core alone — MVP orchestration complete.

---

## Phase 4: User Story 2 - Fleet defined declaratively in git (Priority: P1)

**Goal**: Git is the source of truth — the managed servers/stacks are exactly
those declared under `komodo/`, and a committed change is reflected after a sync.

**Independent Test**: Change a declared value in `komodo/`, commit, re-sync, and
confirm Core reflects the change (via its diff); confirm the managed set equals the
declared set.

### Implementation for User Story 2

- [X] T013 [P] [US2] Create `komodo/variables.toml` with **non-secret** config only (no secret values) to demonstrate git-declared variables (data-model "Variable"; FR-003, FR-006)
- [ ] T014 [US2] Prove git is the source of truth: change a declared value (e.g. retarget the `whoami` stack, or a variable) in `komodo/`, commit, re-sync, and confirm Core's diff reflects it and applies on confirmation; confirm managed == declared (FR-003; SC-002; quickstart 3) — edits `komodo/stacks.toml`/`komodo/variables.toml`

**Checkpoint**: Git changes drive the fleet; managed state equals the declaration.

---

## Phase 5: User Story 3 - Secrets come from mise, never git (Priority: P1)

**Goal**: Stacks receive secrets from the `mise`-rendered environment; no real
secret value appears in any tracked file.

**Independent Test**: Deploy a stack consuming a secret; confirm the value is
injected from the `mise` env and that a `grep` over the tree finds no real value.

### Implementation for User Story 3

- [X] T015 [US3] Add a secret env var to `stacks/whoami/compose.yaml` referenced as `${WHOAMI_TEST_SECRET}`, and add its placeholder to `.mise.toml.example`; ensure the value is in **no** tracked file (research R4; FR-006) — edits `stacks/whoami/compose.yaml` + `.mise.toml.example`
- [ ] T016 [US3] Wire secret delivery: render the secret from `mise` into the **Periphery process environment** (its bootstrap env) so the Periphery-run compose resolves `${VAR}`; deploy and confirm the value reaches the container (research R4; SC-003; quickstart 5) — depends on T015
- [ ] T017 [US3] Bench-validate the `mise → Periphery env → ${VAR}` path; **if** Periphery does not forward its env into compose, switch to the Komodo **secret-Variable `[[VAR]]` fallback** (seed once from the `mise` env, redacted on export) and document which path is used (research R4 flagged risk) — depends on T016
- [X] T018 [US3] Run the secret-free `grep` over `komodo/` + `stacks/` and confirm **zero** real secret values (only `${VAR}`/`[[VAR]]` references) (FR-006; SC-003; contracts/resource-sync-contract.md)

**Checkpoint**: Secrets reach stacks with nothing sensitive in git.

---

## Phase 6: User Story 4 - Deliberate deploy workflow (Priority: P2)

**Goal**: Manual-trigger deploys by default; optional per-stack webhook
auto-deploy.

**Independent Test**: With webhooks off, a git change does not auto-deploy until a
manual trigger; with a per-stack webhook enabled, a push auto-deploys that stack.

### Implementation for User Story 4

- [ ] T019 [US4] Confirm manual-default: commit a change to `stacks/whoami/compose.yaml`, trigger nothing, and verify the running stack is unchanged until a manual sync/deploy (FR-007; SC-004; quickstart 6)
- [ ] T020 [US4] Enable a per-stack **git webhook** for the `whoami` stack and verify a push auto-deploys **only** that stack; other stacks stay manual (research R6; FR-007) — edits `komodo/stacks.toml`

**Checkpoint**: Deploys are manual by default, with opt-in per-stack automation.

---

## Phase 7: Polish & Cross-Cutting Concerns (Verification & Docs)

**Purpose**: Prove conformance to the contracts and quickstart, document the
one-time bring-up, and grow the shareable report. Full behavioral checks require
the two real hosts + a running Core.

- [X] T021 [P] Create `docs/runbooks/phase2-komodo.md`: bootstrap Core + Periphery, create admin/disable registration, configure the ResourceSync, deploy the test stack, the chosen secret-handling path, and **add/remove a node** (FR-011) — one-time bring-up runbook (SC-007, SC-008; FR-012)
- [ ] T022 [P] Run the conformance checks in `contracts/orchestration-contract.md` + `contracts/resource-sync-contract.md`: Core up and LAN-only, both servers healthy, `whoami` on the target node only, secret-free grep, manual-default, add/remove-node is a config change (SC-001..SC-006, SC-008)
- [ ] T023 [P] Run the 8 validation scenarios in `quickstart.md`, including **node independence** (deploy to the Dell while the Mac is offline — SC-005) and **state persistence** (reboot the Dell, confirm Core state intact — SC-006)
- [X] T024 [P] Update `README.md` to record Phase 2: Komodo orchestration live (Core + both agents, git-synced, deploy from one place) (SC-007)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup. **Blocks all user stories.**
- **User Stories (Phases 3–6)**:
  - **US1 (P1)**: After Foundational (needs registered, healthy servers). The MVP.
  - **US2 (P1)**: After Foundational; naturally after US1 (reuses the `whoami`
    stack to demonstrate a git-driven change).
  - **US3 (P1)**: After US1 (adds a secret to the deployed `whoami`).
  - **US4 (P2)**: After US1 (exercises the deploy workflow on `whoami`).
- **Polish (Phase 7)**: Depends on all user stories.

### Within Each Phase

- Foundational: T003/T004/T005 are independent files; T006 depends on T003+T005;
  T007 depends on T006; T008 is independent; T009 depends on T007+T008.
- US1: T010 is independent; T011 needs registered servers (T009) + T010; T012
  depends on T011.
- US3: T015 → T016 → T017 are sequential (same secret path); T018 after them.

### Parallel Opportunities

- Setup: T002 alongside T001.
- Foundational: T003, T004, T005 (different files) together; T008 alongside them.
- US2: T013 independent of the US1 work.
- Polish: T021, T022, T023, T024 — independent, run together.

---

## Parallel Example: Foundational bootstrap files

```bash
# After Setup, author the bootstrap + server files together:
Task: "Create komodo/bootstrap/core.compose.yaml"       # T003
Task: "Create komodo/bootstrap/core.env.example"        # T004
Task: "Create komodo/bootstrap/periphery.compose.yaml"  # T005
Task: "Create komodo/servers.toml"                      # T008
# Then wire the Makefile (T006), bring it up (T007), and sync (T009).
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Complete Phase 1 (Setup) + Phase 2 (Foundational) → control plane up, both
   agents healthy, git-synced.
2. Complete Phase 3 (US1) → deploy the `whoami` test stack to a chosen node from
   Core alone.
3. **STOP and VALIDATE**: a stack deploys to either node from one place, with no
   SSH/compose on the node — the core orchestration deliverable.

### Incremental Delivery

1. Setup + Foundational → the fleet exists and is git-synced.
2. US1 → deploy from one place (MVP core).
3. US2 → git is the source of truth (declarative proof).
4. US3 → secrets from `mise`, nothing in git.
5. US4 → deliberate deploy workflow (manual + optional webhook).
6. Polish → conformance checks, quickstart scenarios, runbook, README.

---

## Notes

- [P] tasks = different files, no dependencies.
- No automated tests requested; verification is the contract/quickstart checks.
- The load-bearing guarantees: **deploy any stack from one place** (SC-001),
  **git is the source of truth** (SC-002), and a **secret-free tree** (SC-003).
- The one open risk (Periphery env forwarding for `${VAR}` secrets, T017) has a
  documented fallback (Komodo secret Variables) — the design does not block on it.
- Komodo/DB images are pinned to a visible major (`:2`), never `:latest`.
- Commit after each task or logical group. Stop at any checkpoint to validate a story.
