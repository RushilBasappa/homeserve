---
description: "Task list for Phase 1 — Migration & Host Provisioning"
---

# Tasks: Phase 1 — Migration & Host Provisioning

**Input**: Design documents from `/specs/002-host-provisioning/`

**Prerequisites**: plan.md (required), spec.md (required), research.md,
data-model.md, contracts/, quickstart.md

**Tests**: No automated test suite is requested — this phase produces provisioning
config and a migration runbook. Verification is by the scriptable conformance
checks in `contracts/` and the scenarios in `quickstart.md` (grouped in the Polish
phase). Full behavioral checks (Docker, NFS) require the two real hosts.

**Organization**: Tasks are grouped by user story so each can be implemented and
verified independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- All paths are relative to the repository root (`/Users/rushilbasappa/Workspace/projects/homeserve`)

## Path Conventions

Infrastructure/documentation monorepo. Provisioning lives in `provision/`, the
one-time runbook in `docs/runbooks/`, and the entry point is a root `Makefile`.
No `src/`/`tests/` tree.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directory skeleton the provisioning and runbook fill in.

- [X] T001 Create the provisioning and runbook directory skeleton: `provision/tasks/`, `provision/group_vars/`, and `docs/runbooks/` (e.g. `mkdir -p provision/tasks provision/group_vars docs/runbooks`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The inventory, shared variables, and `make` entry point every
provisioning task depends on.

**⚠️ CRITICAL**: No provisioning story (US2, US4) can run until this phase is complete.

- [X] T002 [P] Create `provision/inventory.yml` defining hosts `ragnaforge-dell` (10.0.0.70) and `ragnaforge-mac` (10.0.0.71) with groups `dell`, `mac`, and a parent `docker_hosts` (research.md R2)
- [X] T003 [P] Create `provision/group_vars/all.yml` with non-secret variables: `admin_user`, the operator's SSH **public** key, `nfs_export_path` (`/srv/nfs`), the NFS client IP (10.0.0.71), and mount options (research.md R6; data-model "Provisioning Definition")
- [X] T004 Create the root `Makefile` with targets `provision`, `provision-dell`, `provision-mac`, and `check`, each wrapping `mise exec -- ansible-playbook -i provision/inventory.yml provision/playbook.yml [--limit <host>] [--check]` (contracts/provisioning-contract.md; research.md R11)
- [X] T005 [P] Verify `.mise.toml.example` contains a `TAILSCALE_AUTHKEY` placeholder (added in Phase 0); add it if missing (research.md R8)

**Checkpoint**: Inventory + entry point ready — provisioning task files can be filled in.

---

## Phase 3: User Story 1 - Migrate existing data safely via a one-time runbook (Priority: P1) 🎯 MVP

**Goal**: A documented, non-automated runbook that preserves and restores all
irreplaceable data around the OS reinstall, with a verify-before-destroy gate.

**Independent Test**: Follow only the preservation portion of the runbook and
confirm each artifact exists off-box and passes an integrity/restorability check —
before anything is wiped.

### Implementation for User Story 1

- [X] T006 [US1] Create `docs/runbooks/phase1-migration.md` with the ordered steps from `contracts/migration-runbook-contract.md`: **preserve** (snapshot `/srv/nfs` incl. Immich + a Postgres dump; export Vaultwarden, Actual Budget, Home Assistant, *arr configs) → **destination** (external, capacity-checked) → **verify** (integrity + ≥1 test restore) → **STOP gate** → *(reinstall added by US3)* → **`make provision`** → **restore** (FR-001..FR-005)

**Checkpoint**: The data-safety runbook exists and gates destruction on verification.

---

## Phase 4: User Story 2 - Provision a fresh host into a Docker host with one command (Priority: P1) 🎯 MVP

**Goal**: `make provision` takes a freshly installed Debian + SSH host to a ready
Docker host — Docker, NFS, IP forwarding, admin/SSH baseline — idempotently.

**Independent Test**: On a freshly installed node, run the single command and
confirm Docker runs a test container, NFS is mounted read/write, and IP forwarding
is on — with zero manual follow-up.

### Implementation for User Story 2

- [X] T007 [P] [US2] Create `provision/tasks/docker.yml`: install Docker Engine (+ CLI, containerd, compose plugin) from Docker's **official apt repository**, enable the service, add `admin_user` to the `docker` group (FR-009; research.md R3)
- [X] T008 [P] [US2] Create `provision/tasks/ssh-baseline.yml`: ensure `admin_user` exists with the authorized public key and `sudo`/`docker` groups; harden `sshd` via a drop-in (`PasswordAuthentication no`, `PermitRootLogin no`, `PubkeyAuthentication yes`) and reload (FR-012; research.md R6)
- [X] T009 [P] [US2] Create `provision/tasks/sysctl.yml`: persist `net.ipv4.ip_forward=1` via `/etc/sysctl.d/99-ragnaforge.conf` on the Dell using `ansible.posix.sysctl` (FR-011; research.md R5)
- [X] T010 [P] [US2] Create `provision/tasks/nfs-server.yml`: on the Dell, install `nfs-kernel-server`, export `/srv/nfs` to 10.0.0.71 (`rw,sync,no_subtree_check`), apply exports (FR-010; research.md R4)
- [X] T011 [P] [US2] Create `provision/tasks/nfs-client.yml`: on the Mac, install `nfs-common` and mount `/srv/nfs` via systemd automount (`noauto,x-systemd.automount`) so a down server never wedges boot (FR-010, edge case; research.md R4)
- [X] T012 [US2] Create `provision/playbook.yml` orchestrating the US2 task files by host group/role: `docker_hosts` → docker + ssh-baseline; `dell` → sysctl + nfs-server; `mac` → nfs-client (depends on T007–T011; FR-007, FR-013, FR-015)

**Checkpoint**: A fresh node reaches the ready Docker host state from one command — MVP provisioning complete.

---

## Phase 5: User Story 3 - Retire the old k3s cluster as a one-time migration step (Priority: P2)

**Goal**: The incumbent k3s is removed via the fresh OS reinstall, documented in
the migration runbook — never in the automation.

**Independent Test**: Confirm the runbook's reinstall step removes k3s and sits
after the verification gate; confirm `provision/` and the `Makefile` contain no
k3s-teardown logic.

### Implementation for User Story 3

- [X] T013 [US3] Add the **reinstall** step to `docs/runbooks/phase1-migration.md`: freshly install Debian + SSH (which removes the incumbent k3s), placed **after** the verification STOP gate and before `make provision`; state explicitly that k3s removal is NOT part of the reproducible provisioning (FR-006, SC-008) — edits the same file as T006, so it runs after it

**Checkpoint**: k3s retirement is documented as a one-time step, automation stays clean.

---

## Phase 6: User Story 4 - Confirm both nodes are reachable over the personal VPN (Priority: P3)

**Goal**: Tailscale is installed and enrolled on each node (idempotently), and
reachability is verified.

**Independent Test**: From the operator's device, reach each node over Tailscale
and confirm the two nodes can reach each other over the tailnet.

### Implementation for User Story 4

- [X] T014 [P] [US4] Create `provision/tasks/tailscale.yml`: install Tailscale from its **official apt repository**; enroll idempotently by running `tailscale up --authkey "{{ lookup('env','TAILSCALE_AUTHKEY') }}"` **only when** `tailscale status` shows the node is not already connected (FR-017; research.md R7)
- [X] T015 [US4] Add the `tailscale.yml` include to `provision/playbook.yml` for the `docker_hosts` group (edits the same file as T012, so it runs after it)

**Checkpoint**: Both nodes are enrollable and verifiable over Tailscale.

---

## Phase 7: Polish & Cross-Cutting Concerns (Verification)

**Purpose**: Prove the provisioning and runbook conform to the contracts and
quickstart. Full behavioral checks require the two real hosts; the
automation-free grep and runbook checks are host-independent.

- [X] T016 [P] Run the provisioning conformance checks in `contracts/provisioning-contract.md`: idempotency (`make provision` twice → `changed=0`), `docker run --rm hello-world`, `sysctl -n net.ipv4.ip_forward` = 1, `sshd -T` password/root login = no, NFS read/write from the Mac, and the migration-free grep over `provision/`+`Makefile`
- [X] T017 [P] Run the runbook conformance checks in `contracts/migration-runbook-contract.md`: every required-step keyword present in `docs/runbooks/phase1-migration.md`, and the verification gate precedes the reinstall step
- [X] T018 Run the six validation scenarios in `quickstart.md` and confirm expected outcomes for all user stories

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup. Blocks US2 and US4.
- **User Stories (Phases 3–6)**:
  - **US1 (P1)**: After Setup (needs `docs/runbooks/`). Independent of the automation.
  - **US2 (P1)**: After Foundational. The core provisioning deliverable.
  - **US3 (P2)**: After US1 (extends the same runbook file — T013 follows T006).
  - **US4 (P3)**: After US2 (extends `playbook.yml` — T015 follows T012).
- **Polish (Phase 7)**: Depends on all user stories being complete.

### Within Each User Story

- US2: task files T007–T011 are independent of each other; T012 (playbook) depends on all of them.
- US3: T013 edits the US1 runbook — sequential after T006.
- US4: T014 (task file) is independent; T015 edits the US2 playbook — sequential after T012.

### Parallel Opportunities

- Foundational: T002, T003, T005 — different files, run together.
- US2: T007, T008, T009, T010, T011 — different task files, run together.
- Across stories: US1 (T006) is independent of the US2 automation and can proceed in parallel with Phase 4.
- Polish: T016 and T017 are independent and can run together.

---

## Parallel Example: User Story 2 task files

```bash
# After Foundational, create the provisioning task files together:
Task: "Create provision/tasks/docker.yml"        # T007
Task: "Create provision/tasks/ssh-baseline.yml"  # T008
Task: "Create provision/tasks/sysctl.yml"        # T009
Task: "Create provision/tasks/nfs-server.yml"    # T010
Task: "Create provision/tasks/nfs-client.yml"    # T011
# Then T012 wires them into playbook.yml.
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1 (Setup) + Phase 2 (Foundational).
2. Complete Phase 3 (US1) → the data-safety runbook exists.
3. Complete Phase 4 (US2) → `make provision` yields a ready Docker host.
4. **STOP and VALIDATE**: on a freshly installed node, `make provision` reaches the
   ready state idempotently; the runbook safely gates the one-time migration.

### Incremental Delivery

1. Setup + Foundational → inventory + entry point ready.
2. US1 → one-time migration runbook (data safety).
3. US2 → reproducible provisioning (MVP core).
4. US3 → k3s retirement documented in the runbook.
5. US4 → Tailscale enrollment + verification.
6. Polish → run all conformance checks and quickstart scenarios.

---

## Notes

- [P] tasks = different files, no dependencies.
- No automated tests requested; verification is the contract/quickstart checks.
- The load-bearing guarantees: **zero data loss** (runbook verify-before-destroy)
  and **no one-time migration logic in the automation** (SC-008 grep).
- Phase 1's only real secret is `TAILSCALE_AUTHKEY` (already in `.mise.toml.example`).
- Commit after each task or logical group. Stop at any checkpoint to validate a story.

---

## Phase 8: Convergence

Remaining work found by assessing the delivered `provision/` tree against the
spec, plan, and tasks. Appended by `/speckit-converge`; complete with
`/speckit-implement`.

- [X] T019 Add `provision/requirements.yml` declaring the `ansible.posix` collection (used by `sysctl.yml`, `nfs-client.yml`, `ssh-baseline.yml`) and make it installable without an undocumented manual step — e.g. a `make deps` target running `mise exec -- ansible-galaxy collection install -r provision/requirements.yml`, referenced from the README/quickstart — so a fresh control node can run `make provision` reproducibly per SC-009, FR-007 (partial)
- [X] T020 Update `provision/README.md` to reflect the delivered state: it currently says the directory is "Currently empty — populated in Phase 1" and describes Tailscale as "verify present," but the playbook, `tasks/` files, `inventory.yml`, and `group_vars/` now exist and Tailscale is installed + enrolled — align the README with the shipped provisioning per SC-009 (partial)
