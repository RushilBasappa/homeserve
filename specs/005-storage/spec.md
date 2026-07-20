# Feature Specification: Phase 4 — Storage

**Feature Branch**: `005-storage`

**Created**: 2026-07-19

**Status**: Draft

**Input**: User description: "Get started with phase four and I think it should be small"

## Context *(why this phase is small)*

The storage *mechanism* already exists: Phase 1 provisioning (`provision/tasks/nfs-server.yml`, `provision/tasks/nfs-client.yml`) codes the Dell's `/srv/nfs` export and the Mac's `systemd` automount, and `docs/CONVENTIONS.md` already declares the "stateful → Dell" golden rule and the config-vs-media placement matrix. Phase 4 does **not** build a new storage system. It closes three gaps that later phases depend on:

1. **Verify** the coded NFS path actually works end-to-end (server exporting, Mac mount active, read/write both directions) — nothing downstream should assume it works untested.
2. **Materialize** the concrete shared-media directory tree under `/srv/nfs` so Phase 5 (media) and Phase 6 (Immich) have a stable, agreed layout to mount — today the layout is described in prose but the directories do not exist.
3. **Document** the mergerfs + USB growth path that `CONVENTIONS.md` already forward-references as "documented in Phase 4", so a future capacity increase is a known, low-risk procedure rather than an improvisation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A verified, shared media namespace both nodes trust (Priority: P1) 🎯 MVP

As the operator, I need one shared storage namespace that is proven to work from both the Dell and the Mac, with a standard directory layout, so that when I stand up the media stack and photo apps in later phases they can mount known paths without me discovering storage problems mid-build.

**Why this priority**: Phase 5 (media: ARR + Jellyfin) and Phase 6 (Immich) are the highest-value work and both depend on shared storage being real and reliable. A silent NFS or layout problem discovered during those phases is far more expensive to diagnose than one caught now against an empty namespace. This is the phase's MVP: without it, "storage" is only a claim in a playbook.

**Independent Test**: Create a file on `/srv/nfs/<subdir>` from the Dell, read and modify it from the Mac, and observe the change back on the Dell — demonstrating one consistent namespace across both nodes. Confirm the standard directory tree exists and is documented.

**Acceptance Scenarios**:

1. **Given** both nodes provisioned, **When** the operator writes a file under the shared path on the Dell, **Then** the Mac sees the same file with the same contents at the same path.
2. **Given** the Mac has not touched the share since boot, **When** it first accesses the shared path, **Then** the mount activates on demand and the access succeeds without a reboot or manual mount.
3. **Given** the standard media layout is defined, **When** the operator inspects the shared path, **Then** the agreed subdirectories (media library + downloads + photos namespaces) exist and match what `docs/CONVENTIONS.md` documents.
4. **Given** the NFS server is temporarily unavailable, **When** the Mac boots, **Then** boot completes normally and the mount recovers on next access (no wedged boot).

---

### User Story 2 - A documented capacity-growth path (Priority: P2)

As the operator, I need the mergerfs + USB expansion approach written down as a runbook, so that when media outgrows the Dell's internal disk I can add capacity by following a known procedure while the shared export path stays unchanged.

**Why this priority**: Not needed to run today (the internal disk has headroom), but leaving it undocumented turns a future "disk is full" moment into risky improvisation against live data. Cheap to write now while the design is fresh; valuable exactly once, under pressure. Lower than US1 because nothing is blocked on it.

**Independent Test**: A reader unfamiliar with the setup can follow the runbook to understand how a USB disk would be pooled under `/srv/nfs` via mergerfs without changing the NFS export path or any app's mount configuration.

**Acceptance Scenarios**:

1. **Given** the growth-path runbook, **When** the operator reads it, **Then** it explains how added disks are pooled under the existing export path such that consumers (apps, mounts) require no reconfiguration.
2. **Given** `docs/CONVENTIONS.md` references the growth path as "documented in Phase 4", **When** a reader follows that reference, **Then** it resolves to the actual runbook (no dangling promise).

---

### Edge Cases

- **NFS server down at Mac boot**: boot must not block; the automount recovers on next access (already the intent of `noauto,x-systemd.automount` — this phase verifies it).
- **Permission/ownership mismatch across nodes**: a file created on one node must be usable by the app UID that will run on the other; the layout and its ownership must be usable by the later media/photo stacks, not just by the operator's shell.
- **Config accidentally placed on NFS**: the convention forbids app config on NFS (latency/locking); this phase confirms the boundary is documented and the directory tree does not invite config onto the share.
- **Stateful data on the Mac**: the golden rule forbids it; this phase includes a quick audit that no stateful app data currently lives on the Mac.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The shared storage namespace MUST be readable and writable from both the Dell and the Mac at the same path, presenting one consistent view of the same files.
- **FR-002**: The Mac's access to the shared namespace MUST activate on demand and MUST NOT block the Mac's boot when the server is unavailable.
- **FR-003**: A standard directory layout for shared media MUST exist under the export and MUST be documented, covering at minimum the media library, download working area, and photo namespaces that later phases consume.
- **FR-004**: The directory layout's ownership/permissions MUST be usable by the application identities that later phases will run (not only by the operator's interactive login).
- **FR-005**: The "config → local volume on the Dell; shared media → NFS" boundary MUST remain documented, and the created layout MUST NOT place app configuration on the shared namespace.
- **FR-006**: The mergerfs + USB capacity-growth path MUST be documented as a runbook, and MUST state that adding capacity leaves the export path (and therefore every consumer's mount) unchanged.
- **FR-007**: The phase MUST confirm (audit) that no stateful application data currently resides on the Mac, upholding the golden rule before later stateful stacks land.
- **FR-008**: Verification of FR-001 and FR-002 MUST be recorded (e.g. in the phase runbook) so the "storage works" claim is evidenced, not assumed.

### Key Entities *(include if feature involves data)*

- **Shared media namespace**: the single `/srv/nfs`-rooted tree exported by the Dell and mounted on the Mac; the one place both nodes and future app stacks read/write shared media.
- **Standard directory layout**: the agreed subdirectory structure within that namespace (media library, downloads, photos) that Phase 5 and Phase 6 stacks mount by known path.
- **Growth-path runbook**: the document describing how additional physical capacity is pooled under the existing export without changing consumer configuration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A file created on either node is visible with identical contents on the other node within seconds, with zero manual mount steps on the accessing node.
- **SC-002**: Rebooting the Mac while the server is down completes boot normally, and the shared path becomes accessible on first access afterward — no reboot loop, no manual intervention.
- **SC-003**: 100% of the media/download/photo subdirectories that Phase 5 and Phase 6 will mount already exist and are listed in `docs/CONVENTIONS.md` before those phases begin.
- **SC-004**: A reader can locate the mergerfs + USB growth runbook from the existing `CONVENTIONS.md` reference in one hop, and it correctly states the export path is unaffected by capacity additions.
- **SC-005**: The audit finds no stateful application data on the Mac (result recorded), or any exception is explicitly documented with justification.

## Assumptions

- The NFS server/client Ansible tasks from Phase 1 are the intended mechanism and are re-runnable; Phase 4 verifies and, where needed, extends them rather than replacing them.
- Both nodes are provisioned and reachable on the LAN (10.0.0.70 Dell / 10.0.0.71 Mac) as established in earlier phases.
- The Dell's internal disk has sufficient free space for near-term media; mergerfs + USB is a documented future path, **not** something to stand up in this phase.
- The standard directory layout should serve the already-planned consumers — the ARR + Jellyfin media stack (Phase 5) and Immich (Phase 6) — so their expected mount points shape the tree.
- No offsite/backup concerns are in scope here; backups are Phase 9. This phase only makes the shared namespace real, verified, and documented.

## Out of Scope

- Standing up mergerfs or attaching a USB disk (documented as a future path only).
- Any application stack that consumes the storage (Phases 5, 6).
- Backups, snapshots, or offsite replication of the namespace (Phase 9).
- Changing the NFS transport, authentication, or the single-client export model established in Phase 1.
