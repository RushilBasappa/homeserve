# Tasks: Phase 4 — Storage

**Input**: Design documents from `/specs/005-storage/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/media-layout.md, quickstart.md

**Tests**: No automated test tasks — this phase is verified **behaviorally** per
`quickstart.md` (cross-node consistency, automount, boot resilience). No TDD was
requested and there is no application code to unit-test.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 (Setup, Foundational, Polish carry no story label)

## Build order at a glance

1. **Setup** → runbook scaffold to record everything into.
2. **Foundational** → create the tree in Ansible + apply (the substrate US1 verifies).
3. **US1 (P1, MVP)** → prove one consistent, correctly-owned namespace + audit the Mac.
4. **US2 (P2)** → document the mergerfs + USB growth path and resolve the dangling ref.
5. **Polish** → consolidate evidence, mark status, sanity checks.

## Implementation status (2026-07-19)

- **Complete.** The media tree is materialized under `/srv/nfs`
  (`provision/tasks/storage-layout.yml`, wired into `playbook.yml` on the Dell,
  applied idempotently — second pass `changed=0`). All six `quickstart.md` checks
  pass: cross-node write/read consistency, on-demand automount, server-down boot
  resilience, the Mac stateful-data audit (clean bar the Komodo Periphery agent
  itself), and the growth-path reference resolves. Evidence recorded in
  `docs/runbooks/phase4-storage.md`; `CONVENTIONS.md`, `README.md`, `PLAN.md`
  updated. No secrets introduced; nothing config-related placed under `/srv/nfs`.

---

## Phase 1: Setup

**Purpose**: A single place to record layout, verification evidence, and the growth path.

- [X] T001 Create the Phase-4 runbook skeleton `docs/runbooks/phase4-storage.md` with sections: `Standard layout`, `Verification evidence (SC-001..005)`, `Mergerfs + USB growth path`, `Mac stateful-data audit` (mirrors the Phase 1–3 runbook style)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the shared directory tree reproducibly. **Blocks US1** (there is
nothing to verify until the tree exists). US2 is docs-only and does not depend on this.

⚠️ These tasks mutate the real hosts (run via `mise` + Ansible; needs SSH to the Dell).

- [X] T002 Create `provision/tasks/storage-layout.yml` — an idempotent task that creates the tree from `contracts/media-layout.md` (`/srv/nfs/media/{movies,tv}`, `/srv/nfs/downloads/{complete,incomplete}`, `/srv/nfs/photos`) with owner `1000:1000` and dir mode `2775` (setgid), per research R2/R3. Loop over the path list; `state: directory`, no `recurse` onto the NFS root itself
- [X] T003 Wire `storage-layout.yml` into `provision/playbook.yml` so it runs **on the Dell only** (the server owns the real directories; the Mac sees them through the mount), sequenced after `nfs-server.yml`
- [X] T004 Apply `provision/playbook.yml` (via the project `mise`/Makefile flow), then re-run and confirm **idempotence** — the storage-layout tasks report `ok`/unchanged on the second pass

**Checkpoint**: `ls -la /srv/nfs/media /srv/nfs/downloads` on the Dell shows the tree owned `rushil:rushil 2775`.

---

## Phase 3: User Story 1 - A verified, shared media namespace both nodes trust (Priority: P1) 🎯 MVP

**Goal**: Prove one consistent namespace across the Dell and the Mac, with the standard
layout and correct ownership, and confirm the Dell is the single source of truth.

**Independent test**: Run `quickstart.md` Checks 1–5 — write on the Dell, read/modify on
the Mac, confirm on-demand automount and server-down boot resilience, and audit that no
stateful data lives on the Mac. All pass and are recorded.

- [X] T005 [US1] Run `quickstart.md` **Check 1** (tree exists, each leaf `rushil:rushil 2775`); paste output into the `Standard layout` section of `docs/runbooks/phase4-storage.md` (SC-003, FR-003/FR-004)
- [X] T006 [US1] Run `quickstart.md` **Check 2** (write on Dell → read on Mac → append on Mac → visible on Dell); record result (SC-001, FR-001)
- [X] T007 [US1] Run `quickstart.md` **Check 3** (`srv-nfs.automount` active; first access mounts on demand; `findmnt` shows the nfs mount); record result (SC-001, FR-002)
- [X] T008 [US1] Run `quickstart.md` **Check 4** (stop `nfs-server`, confirm the Mac's automount comes up without hanging, restore server, access recovers on next touch); record result (SC-002, FR-002, edge case)
- [X] T009 [US1] Run `quickstart.md` **Check 5** — audit that no Docker named volume / bind mount on the Mac holds a database or app config; record the result (and justify any exception) in the `Mac stateful-data audit` section (SC-005, FR-007)
- [X] T010 [US1] Confirm/extend the storage layout table in `docs/CONVENTIONS.md` so it matches the materialized tree **exactly** (paths, ownership, "config never on NFS" boundary) (FR-003, FR-005)

**Checkpoint**: MVP complete — the shared namespace is real, proven cross-node, and the golden rule is verified. Phases 5/6 could mount `contracts/media-layout.md` paths from here.

---

## Phase 4: User Story 2 - A documented capacity-growth path (Priority: P2)

**Goal**: The mergerfs + USB expansion is written down so a future "disk full" moment is
a known procedure, and the existing `CONVENTIONS.md` promise resolves to it.

**Independent test**: A reader follows the `CONVENTIONS.md` "documented in Phase 4"
reference in one hop to a runbook that explains pooling a USB disk under `/srv/nfs`
without changing the export path or any app mount.

- [X] T011 [P] [US2] Write the `Mergerfs + USB growth path` section in `docs/runbooks/phase4-storage.md` per research R5: how a USB disk is pooled under `/srv/nfs` via mergerfs, with the explicit invariant that the export path — and every app mount — stays unchanged (SC-004, FR-006)
- [X] T012 [US2] Update the "documented in Phase 4" reference in `docs/CONVENTIONS.md` to link `docs/runbooks/phase4-storage.md`, resolving the dangling forward-reference (SC-004, US2 acceptance #2)

**Checkpoint**: The growth path is documented and reachable; no dangling promise remains.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T013 Consolidate all six `quickstart.md` check outputs under `Verification evidence` in `docs/runbooks/phase4-storage.md`, then update the **Implementation status** line in this `tasks.md` and mark the Phase 4 deliverable in `PLAN.md` / `README.md` as done (matching how Phases 1–3 recorded completion)
- [X] T014 [P] Sanity pass: confirm the change set introduces **no secrets** (`git grep` for tokens/passwords in the new files) and that `storage-layout.yml` places nothing config-related under `/srv/nfs` (upholds the config-off-NFS boundary)

---

## Dependencies & execution order

- **Setup (T001)** → first; both stories record into the runbook it scaffolds.
- **Foundational (T002 → T003 → T004)** → strictly ordered; blocks **US1**. T003 depends on T002 (includes the file it creates); T004 depends on both.
- **US1 (T005–T010)** → after Foundational. T005–T009 are the quickstart checks (run in listed order; T008 is the disruptive one — do when convenient). T010 can follow once the tree is confirmed.
- **US2 (T011–T012)** → independent of Foundational/US1 (docs-only); can proceed any time after Setup. **T011 [P]** may run parallel to US1 work (different file section vs. live checks).
- **Polish (T013–T014)** → last; T014 [P] can run alongside T013.

## Parallel opportunities

- **US2 in parallel with US1**: T011 (write growth-path docs) needs no live hosts and can be written while US1's verification checks run.
- Within Polish: **T014 [P]** (secret/config sanity) runs alongside **T013** (evidence consolidation).
- Foundational and US1 verification steps are inherently sequential (each verifies the prior state / writes the same runbook file), so they are **not** marked [P].

## MVP scope

**Setup + Foundational + US1 (T001–T010)** = the MVP: a materialized, verified,
correctly-owned shared namespace with the golden rule audited. US2 (docs) and Polish
complete the phase but are not required to unblock Phase 5/6 mounting.
