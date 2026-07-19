---

description: "Task list for Phase 0 — Foundation & Repo Scaffolding"
---

# Tasks: Phase 0 — Foundation & Repo Scaffolding

**Input**: Design documents from `/specs/001-repo-scaffolding/`

**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: No automated test suite is requested — this phase produces documentation
and repository structure only. Verification is by inspection plus the scriptable
conformance checks in `contracts/` and `quickstart.md` (grouped in the Polish phase).

**Organization**: Tasks are grouped by user story so each can be implemented and
verified independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- All paths are relative to the repository root (`/Users/rushilbasappa/Workspace/projects/homeserve`)

## Path Conventions

Infrastructure/documentation monorepo. Artifacts live at the repository root
(`stacks/`, `provision/`, `komodo/`, `docs/`, plus root files). No `src/`/`tests/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the top-level directory skeleton every user story fills in.

- [X] T001 Create the top-level directory skeleton at repo root: `stacks/`, `provision/`, `komodo/`, `docs/` (e.g. `mkdir -p stacks provision komodo docs`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish version control so `.gitignore` behavior and the
no-real-secrets guarantee can be verified.

**⚠️ CRITICAL**: No user story work should be verified until this phase is complete.

- [X] T002 Initialize a Git repository at the repo root (`git init`) so `.gitignore` and `git check-ignore` verification (SC-004) work

**Checkpoint**: Skeleton + version control ready — user stories can now proceed.

---

## Phase 3: User Story 1 - Clone a self-documenting repo (Priority: P1) 🎯 MVP

**Goal**: A fresh clone explains its own layout — each top-level directory's
purpose is documented and the README is the entry point linking the master plan
and conventions.

**Independent Test**: From a fresh clone, using only the README and directory
structure, correctly state what goes in `stacks/`, `provision/`, `komodo/`, and
`docs/`, and locate `PLAN.md` and `docs/CONVENTIONS.md`.

### Implementation for User Story 1

- [X] T003 [P] [US1] Create `stacks/README.md` documenting the "one directory per Compose stack" convention
- [X] T004 [P] [US1] Create `provision/README.md` describing the lean Ansible provisioning directory
- [X] T005 [P] [US1] Create `komodo/README.md` describing the Komodo resource-sync definitions directory
- [X] T006 [US1] Create `README.md` at repo root with: project purpose, current phase status (Phase 0), and links to `PLAN.md` and `docs/CONVENTIONS.md` (FR-005, FR-012)

**Checkpoint**: The repo is self-documenting from static files — MVP complete.

---

## Phase 4: User Story 2 - Handle secrets safely from day one (Priority: P1)

**Goal**: Every required secret is visible as a placeholder, and no real secret
can be committed.

**Independent Test**: Inspect `.mise.toml.example` and `.gitignore`; copy the
example to `.mise.toml` and confirm version control reports the real file as
ignored while the example stays tracked.

### Implementation for User Story 2

- [X] T007 [P] [US2] Create `.mise.toml.example` with placeholder-only entries for every secret referenced by `PLAN.md` — at minimum Cloudflare API token, commercial-VPN WireGuard egress credentials, and Tailscale auth key — each with a one-line comment (FR-006, FR-007, contracts/secrets-example.md)
- [X] T008 [P] [US2] Create `.gitignore` excluding `.mise.toml`, `.env`, `*.env`, and generated/rendered artifacts (FR-008)

**Checkpoint**: Secrets pattern in place; repo is safe to share publicly.

---

## Phase 5: User Story 3 - Follow one set of conventions (Priority: P2)

**Goal**: A single document governs naming, ports, routing labels, data
placement, and the add-an-app procedure.

**Independent Test**: Using only `docs/CONVENTIONS.md`, describe how a
hypothetical new app is named, where its config and media data live, and the
new-app checklist steps.

### Implementation for User Story 3

- [X] T009 [US3] Create `docs/CONVENTIONS.md` covering: stack/container/host naming, port allocation, Traefik routing-label conventions, the "stateful data → Dell" rule (config vs. shared media placement), and a step-by-step new-app checklist (FR-009, FR-010, FR-011)

**Checkpoint**: Conventions are followable end-to-end without asking questions.

---

## Phase 6: User Story 4 - README grows into the shareable report (Priority: P3)

**Goal**: The README is structured so each later phase appends its section, and
contains no real secrets.

**Independent Test**: Review the README outline — it contains labeled,
initially-empty sections aligned to the plan's phases.

### Implementation for User Story 4

- [X] T010 [US4] Extend `README.md` with a phase-aligned outline: placeholder sections for Phases 1–12 ready for later phases to fill (FR-012) — depends on T006
- [X] T011 [US4] Review `README.md` and confirm it contains no real secret values, only references to the `.mise.toml.example` placeholder pattern (FR-013)

**Checkpoint**: README is the growing shareable-report skeleton.

---

## Phase 7: Polish & Cross-Cutting Concerns (Verification)

**Purpose**: Prove the whole scaffolding conforms to the contracts and quickstart.

- [X] T012 [P] Run the repo-structure conformance checks in `contracts/repo-structure.md`; expect no output (all required paths present, README links resolve)
- [X] T013 [P] Run the secrets conformance checks in `contracts/secrets-example.md`: verify `.mise.toml.example` enumerates the plan's secrets, and that `cp .mise.toml.example .mise.toml && git check-ignore -q .mise.toml` reports it ignored (SC-002, SC-003, SC-004)
- [X] T014 Run the five validation scenarios in `quickstart.md` and confirm expected outcomes for all user stories

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup.
- **User Stories (Phases 3–6)**: All depend on Foundational (Phase 2). US1, US2,
  US3 are mutually independent. US4 depends on US1 (extends the same `README.md`).
- **Polish (Phase 7)**: Depends on all user stories being complete.

### User Story Dependencies

- **US1 (P1)**: After Foundational. No dependencies on other stories.
- **US2 (P1)**: After Foundational. Fully independent.
- **US3 (P2)**: After Foundational. Independent (US1's README may link to
  `CONVENTIONS.md` before it exists — a forward reference, not a build dependency).
- **US4 (P3)**: After US1 (both edit `README.md`, so T010 must follow T006).

### Within Each User Story

- Directory READMEs (T003–T005) are independent of the root README (T006).
- T010 (US4) must run after T006 (US1) — same file.

### Parallel Opportunities

- T003, T004, T005 (US1 directory READMEs) — different files, run together.
- T007, T008 (US2) — different files, run together.
- Across stories: once Foundational is done, US1, US2, and US3 can proceed in
  parallel by different people. US4 waits on T006.
- Polish checks T012 and T013 are independent and can run together.

---

## Parallel Example: User Story 1 + User Story 2

```bash
# After Phase 2, launch the independent doc-creation tasks together:
Task: "Create stacks/README.md"          # T003
Task: "Create provision/README.md"        # T004
Task: "Create komodo/README.md"           # T005
Task: "Create .mise.toml.example"         # T007  (US2, independent of US1)
Task: "Create .gitignore"                 # T008  (US2, independent of US1)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup) + Phase 2 (Foundational).
2. Complete Phase 3 (US1) → the repo is self-documenting.
3. **STOP and VALIDATE**: fresh-clone test — a newcomer identifies every
   directory's purpose in under 5 minutes (SC-001).

### Incremental Delivery

1. Setup + Foundational → skeleton + version control ready.
2. US1 → self-documenting repo (MVP).
3. US2 → safe secret handling → repo becomes publicly shareable.
4. US3 → conventions locked in for all later phases.
5. US4 → README is the growing shareable report.
6. Polish → run all conformance checks and quickstart validation.

### Parallel Team Strategy

After Foundational: Developer A takes US1 (→ then US4), Developer B takes US2,
Developer C takes US3. All three finish independently; converge on the Polish
verification.

---

## Notes

- [P] tasks = different files, no dependencies.
- No automated tests requested; verification is inspection + contract/quickstart checks.
- The load-bearing guarantee: no tracked file contains a real secret (FR-013, SC-003).
- Commit after each task or logical group.
- Stop at any checkpoint to validate a story independently.
