# Implementation Plan: Phase 4 — Storage

**Branch**: `005-storage` | **Date**: 2026-07-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-storage/spec.md`

## Summary

Make the shared storage namespace **real, verified, and documented** — without
building a new storage system. The NFS *mechanism* already ships in Phase 1
(`provision/tasks/nfs-server.yml` exports `/srv/nfs` from the Dell;
`provision/tasks/nfs-client.yml` mounts it on the Mac via `systemd` automount),
and `docs/CONVENTIONS.md` already declares the "stateful → Dell" golden rule and
the config-vs-media placement matrix. This phase closes the three gaps later
phases depend on:

1. **Materialize the layout.** Create the concrete, hardlink-friendly directory
   tree under `/srv/nfs` (`media/{movies,tv}`, `downloads/{complete,incomplete}`,
   `photos/`) with shared group ownership + `setgid` so every future app writes
   files the others can read. Today the tree is prose in `CONVENTIONS.md`; the
   directories do not exist. Codified as a small, idempotent Ansible task so it is
   reproducible on a fresh build — not a one-off `mkdir` over SSH.
2. **Verify end-to-end.** Prove one consistent namespace: write on the Dell → read
   on the Mac → modify back; confirm the Mac's automount activates on demand and a
   server-down boot does not wedge. Record the evidence in a runbook.
3. **Document the growth path.** Write the mergerfs + USB runbook that
   `CONVENTIONS.md` already forward-references as "documented in Phase 4", stating
   that pooling added disks under the export leaves the path — and every consumer's
   mount — unchanged. Plus a quick audit that no stateful data lives on the Mac.

**No application services** are deployed here; the tree stays empty until Phase 5
(ARR + Jellyfin) and Phase 6 (Immich) mount it.

## Technical Context

**Language/Version**: No application language. Infrastructure-as-config: **Ansible**
(`provision/tasks/*.yml`, run via `provision/playbook.yml`) for the directory tree,
extending the existing NFS tasks; **Markdown** runbooks under `docs/runbooks/`. `mise`
already renders the one secret (`ANSIBLE_BECOME_PASSWORD`); this phase adds none.

**Primary Dependencies**: The Phase-1 NFS stack — `nfs-kernel-server` (Dell),
`nfs-common` (Mac), `ansible.posix.mount` automount — all already provisioned. No new
packages required for the delivered scope. `mergerfs` is *documented* as a future
package, not installed here.

**Storage**: The subject of the phase. One export, `/srv/nfs`, on the **Dell's**
238 GB NVMe (golden rule), mounted at the same path on the Mac. Shared **media**
lives under this tree; app **config/state** does **not** (stays in local named
volumes on the Dell, per `CONVENTIONS.md`). Ownership model: a shared PUID/PGID
(`1000:1000`, the `rushil` account already provisioned) with `2775` (setgid)
directories so files created by any media app are group-readable/writable by the
others — the precondition for cross-app hardlinks and Jellyfin/Immich reads.

**Testing**: No unit suite — behavioral validation per `quickstart.md`, mapped to
SC-001…SC-005: cross-node write/read consistency; on-demand automount with no manual
step; server-down Mac boot completes then recovers on access; the full media/downloads/
photos tree exists and matches `CONVENTIONS.md`; the growth runbook resolves from the
`CONVENTIONS.md` reference; the Mac stateful-data audit is recorded.

**Target Platform**: `ragnaforge-dell` (10.0.0.70) is the NFS server and the single
source of truth; `ragnaforge-mac` (10.0.0.71) is the sole permitted client (the
export is pinned to its IP, not the whole `/24`). LAN `10.0.0.0/24`.

**Project Type**: Infrastructure/documentation monorepo. Changes land in
`provision/tasks/` (new `storage-layout.yml`), `provision/playbook.yml` (wire it in),
`docs/CONVENTIONS.md` (confirm/extend the layout table), and
`docs/runbooks/phase4-storage.md` (verification evidence + mergerfs growth path).

**Performance Goals**: N/A. Practical: NFS over gigabit LAN is ample for library
reads and playback; the design constraint that matters is *correctness* — downloads
and media on one filesystem so servarr moves are instant hardlinks/atomic renames,
not slow cross-device copies.

**Constraints**: Config MUST NOT land on NFS (latency/locking) — enforced by
convention and by the tree shape (no `config/` under the export). The export model,
transport, and single-client restriction from Phase 1 are **unchanged**. Adding
capacity later MUST NOT change the export path.

**Scale/Scope**: Small. One Ansible task file, one playbook wire-in, one runbook, a
`CONVENTIONS.md` touch-up, and a verification pass. No new stacks, no new secrets, no
new public surface.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an **unfilled
template** — no ratified principles, so there are no formal gates to evaluate. The
project's *de facto* principles from `PLAN.md` / `CONVENTIONS.md` are nonetheless
upheld by this plan:

- **Stateful → Dell**: the export lives on the Dell; config stays off NFS. ✅
- **Minimal custom code / off-the-shelf**: reuses Phase-1 NFS + standard servarr
  layout; the only "code" is one idempotent Ansible task and Markdown. ✅
- **Reproducible from git**: the tree is provisioned by Ansible, not hand-`mkdir`'d,
  so a clean rebuild reproduces it. ✅
- **No secrets in the repo**: this phase introduces no secrets. ✅

**Result: PASS** (no violations; Complexity Tracking not required).

## Project Structure

### Documentation (this feature)

```text
specs/005-storage/
├── plan.md              # This file
├── research.md          # Phase 0 output — layout & ownership decisions
├── data-model.md        # Phase 1 output — the namespace as an entity model
├── quickstart.md        # Phase 1 output — the verification runbook (SC-001…005)
├── contracts/
│   └── media-layout.md  # Phase 1 output — the directory-tree contract Phase 5/6 mount
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
provision/
├── tasks/
│   ├── nfs-server.yml       # (existing) Dell export — verified, unchanged
│   ├── nfs-client.yml       # (existing) Mac automount — verified, unchanged
│   └── storage-layout.yml   # NEW — idempotent creation of the media tree + setgid
└── playbook.yml             # EDIT — include storage-layout.yml on the Dell

docs/
├── CONVENTIONS.md           # EDIT — confirm/extend the storage layout table
└── runbooks/
    └── phase4-storage.md    # NEW — verification evidence + mergerfs+USB growth path
```

**Structure Decision**: Infrastructure/documentation monorepo (matching Phases 1–3).
The delivered artifact is one new Ansible task file wired into the existing
`playbook.yml`, one new runbook, and a `CONVENTIONS.md` touch-up — no `src/`, no new
stack. The "storage system" is the existing NFS export; this phase adds its *contents
and proof*, keeping everything reproducible from git.

## Complexity Tracking

> No Constitution Check violations — section intentionally empty.
