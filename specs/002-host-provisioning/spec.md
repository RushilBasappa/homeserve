# Feature Specification: Phase 1 — Migration & Host Provisioning

**Feature Branch**: `002-host-provisioning`

**Created**: 2026-07-18

**Status**: Draft

**Input**: User description: "Ready for Phase 1"

## Overview

Phase 1 has two clearly separated concerns:

1. **Reusable provisioning (the repo deliverable)** — a single reproducible
   command that turns a **freshly installed Debian host reachable over SSH** into
   a ready Docker host (Docker Engine, shared NFS storage, kernel networking,
   admin/SSH baseline). This is idempotent, node-agnostic, and reused whenever a
   host is added or rebuilt.
2. **A one-time migration (a documented runbook, not automation)** — for the two
   *current* laptops only: preserve the ~103 GB of media, Immich photos, and the
   app configs worth keeping; reinstall the OS fresh (which inherently removes the
   incumbent k3s); then restore the preserved data. Because this happens once, it
   lives as a runbook in `docs/`, **not** in the reproducible provisioning.

No application services are deployed in this phase — it produces the clean
foundation every later phase drops Compose stacks onto. The "user" throughout is
the **operator** reproducing the server.

## Clarifications

### Session 2026-07-18

- Q: How should the one-time k3s removal be represented in the repo? → A: Not
  automated — captured as a one-time **migration runbook** in `docs/`, while the
  reproducible provisioning assumes a freshly installed OS with no k3s present.
- Q: Where does the one-time data preservation belong (media/photo snapshot +
  app-config exports before the OS is wiped)? → A: The **same** one-time migration
  runbook (preserve → reinstall → restore), not part of `make provision`.
- Q: Which provisioning tool should Phase 1 use (Ansible vs. modern alternatives
  such as pyinfra or NixOS)? → A: **Ansible** — kept. Alternatives were evaluated
  (pyinfra: leaner but less widely known; NixOS: maximal reproducibility but a
  whole-OS paradigm shift) and rejected for this small scope; Ansible's ubiquity
  best serves "reproducible by a competent friend."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Migrate existing data safely via a one-time runbook (Priority: P1)

As the operator, before I reinstall the OS on the current laptops I can follow a
documented runbook that captures a verified, restorable copy of everything I
cannot recreate — the media library, Immich photos, and the configs of apps worth
keeping (Vaultwarden, Actual Budget, Home Assistant, the *arr apps) — and then
restores it after provisioning, so a fresh install can never cost me that data.

**Why this priority**: Data loss here is irreversible and catastrophic (family
photos, password vault, financial records). A fresh OS install wipes the Dell's
single disk, so preservation-then-restore is the gate that must succeed around any
destructive step — the single most important outcome of this phase.

**Independent Test**: Follow only the preservation portion of the runbook, then
confirm each artifact exists in a location independent of the machine being
reinstalled and passes an integrity/restorability check — all before anything is
wiped.

**Acceptance Scenarios**:

1. **Given** the current running machines, **When** the operator follows the
   runbook's preservation steps, **Then** a snapshot of the shared media/photo
   store and an export of each listed app's configuration exist in a location that
   survives an OS reinstall.
2. **Given** a completed preservation, **When** the operator verifies it, **Then**
   every artifact reports an integrity-check pass and at least one config export
   is demonstrably restorable (a test restore succeeds).
3. **Given** preservation has **not** been verified, **When** the runbook reaches
   a destructive step (wipe/reinstall), **Then** the runbook directs the operator
   to stop until the missing/unverified artifact is resolved.
4. **Given** provisioning is complete on the fresh OS, **When** the operator runs
   the runbook's restore steps, **Then** the preserved media/photos and app
   configs are back in place and readable.

---

### User Story 2 - Provision a fresh host into a Docker host with one command (Priority: P1)

As the operator, starting from a **freshly installed Debian host reachable over
SSH**, I can run a single command that brings it to a ready Docker host — Docker
Engine installed, shared storage (NFS) in place, required kernel networking
enabled, and a consistent admin/SSH baseline — so that standing up or rebuilding a
host is reproducible from the repository, not remembered manual steps.

**Why this priority**: This is the phase's reusable deliverable — the reproducible
foundation every later phase depends on, and the same recipe used to add future
nodes (including the eventual Mac Mini).

**Independent Test**: On a freshly installed node, run the single provisioning
command and confirm Docker runs a test container, shared storage is mounted and
read/write, and IP forwarding is enabled — with zero manual follow-up steps and no
manual pre-cleanup required.

**Acceptance Scenarios**:

1. **Given** a freshly installed node reachable over SSH, **When** the operator
   runs the provisioning command, **Then** the node ends in the "ready Docker
   host" state (Docker running, NFS configured, IP forwarding on, admin/SSH
   baseline applied) with no manual post-steps.
2. **Given** an already-provisioned node, **When** the operator runs the same
   command again, **Then** it reports no changes needed (idempotent).
3. **Given** both nodes provisioned, **When** the operator runs a container on the
   Mac that reads and writes the Dell's shared storage, **Then** the read/write
   succeeds over NFS.
4. **Given** the provisioning definition, **When** the operator inspects it,
   **Then** it contains no one-time migration steps (no data preservation, k3s
   teardown, or OS reinstall) — those live only in the migration runbook.

---

### User Story 3 - Retire the old k3s cluster as a one-time migration step (Priority: P2)

As the operator, I remove the old k3s cluster from the current laptops as part of
the one-time migration — achieved by the fresh OS install — with the steps
captured in the migration runbook, so nothing of k3s lingers to interfere with
Docker, and the reusable provisioning stays free of one-off teardown logic.

**Why this priority**: Required to reach clean hosts, but it is a one-time concern
subordinate to preservation (P1) and provisioning (P1), and is realized simply by
the fresh install rather than bespoke automation.

**Independent Test**: After the migration, inspect each node and confirm no k3s
process, service, or leftover mount/interface/rule remains; confirm the repo's
provisioning contains no k3s-teardown steps.

**Acceptance Scenarios**:

1. **Given** verified preservation, **When** the operator follows the runbook to
   reinstall the OS, **Then** the incumbent k3s and its state are gone from both
   nodes.
2. **Given** the migration is complete, **When** the operator inspects each node,
   **Then** no k3s service runs and no k3s-created mounts, interfaces, or firewall
   rules remain to interfere with Docker.

---

### User Story 4 - Confirm both nodes are reachable over the personal VPN (Priority: P3)

As the operator, I can confirm both nodes are reachable over Tailscale after
provisioning, so I can manage them remotely and later phases can rely on that
private connectivity.

**Why this priority**: Valuable confirmation, but the lowest-impact slice of the
phase. On a freshly installed OS, Tailscale enrollment is part of bringing the
node online; this story ensures the end state is verified.

**Independent Test**: From the operator's device, reach each node over its
Tailscale identity and confirm the two nodes can reach each other over the tailnet.

**Acceptance Scenarios**:

1. **Given** provisioned nodes, **When** the operator checks the tailnet, **Then**
   both nodes appear online and are reachable over Tailscale.
2. **Given** a node missing from the tailnet, **When** the operator runs the
   enrollment step, **Then** the node is (re-)enrolled and becomes reachable.

---

### Edge Cases

- **Preservation verification fails** (corrupt snapshot, failed test restore): the
  runbook halts before any wipe/reinstall and tells the operator which artifact
  failed.
- **Snapshot destination lacks capacity** for the ~103 GB set: the runbook has the
  operator confirm sufficient space before producing a partial, misleading backup.
- **A node is offline/unreachable** during provisioning: provisioning of the
  reachable node proceeds independently; the unreachable node is reported, not
  silently treated as done.
- **Provisioning re-run after a partial failure**: a second run converges the node
  to the desired state without duplicating or corrupting prior work.
- **Provisioning run against a non-fresh host** (unexpected leftover software): the
  reproducible provisioning assumes a fresh OS; leftover cluster software is a
  runbook/migration concern, not something provisioning is expected to clean up.
- **Restore after provisioning**: restoring preserved data onto the freshly
  provisioned Dell reproduces the original media/config layout without conflicting
  with the new Docker/NFS setup.
- **Shared storage unavailable when the Mac boots**: the mount behavior is defined
  so a temporarily-absent NFS server does not wedge the Mac.

## Requirements *(mandatory)*

### Functional Requirements

**One-time migration runbook (US1, US3)**

- **FR-001**: A one-time migration runbook (in `docs/`) MUST document capturing a
  restorable snapshot of the shared media/photo store (~103 GB `/srv/nfs`,
  including Immich photos) before the OS is reinstalled.
- **FR-002**: The runbook MUST document exporting the configuration of each app
  worth keeping — at minimum Vaultwarden, Actual Budget, Home Assistant, and the
  *arr apps — before reinstall.
- **FR-003**: The runbook MUST direct preserved artifacts to a location that
  survives an OS reinstall (independent of the machine being rebuilt).
- **FR-004**: The runbook MUST include verifying preserved artifacts are restorable
  (integrity check plus at least one demonstrated test restore) before any
  destructive step.
- **FR-005**: The runbook MUST order steps so verification precedes any wipe/
  reinstall, and MUST document restoring the preserved data after provisioning.
- **FR-006**: Removal of the incumbent k3s MUST be handled by the one-time
  migration — either via a fresh OS install or an equivalent one-time in-place
  teardown (as-built: `scripts/cleanup-*.sh`, which removes k3s/Docker/data while
  preserving SSH) — and documented in the runbook; it MUST NOT be part of the
  reproducible provisioning automation.

**Reproducible provisioning (US2)**

- **FR-007**: The repository MUST provide a single reproducible command that
  provisions a node into a ready Docker host.
- **FR-008**: Provisioning MUST assume a freshly installed Debian OS reachable over
  SSH as its starting state, with no dependency on any prior cluster software.
- **FR-009**: Provisioning MUST install and enable Docker Engine.
- **FR-010**: Provisioning MUST configure shared storage: the Dell exports the
  shared media/config store over NFS and the Mac mounts it.
- **FR-011**: Provisioning MUST enable the kernel networking required for a future
  VPN subnet router (IP forwarding).
- **FR-012**: Provisioning MUST apply a consistent administrative user and SSH
  access baseline on both nodes.
- **FR-013**: Provisioning MUST be idempotent — safe to re-run, converging to the
  same desired state and reporting no changes when already applied.
- **FR-014**: Provisioning MUST remain lean and maintainable — a small, readable
  set of tasks rather than the previous heavyweight role structure.
- **FR-015**: Each node MUST be provisionable independently, so one unreachable
  node does not block the other.
- **FR-016**: Provisioning MUST NOT contain one-time migration steps (data
  preservation, k3s teardown, or OS reinstall); those live only in the runbook.

**Connectivity verification (US4)**

- **FR-017**: Both nodes MUST be confirmed reachable over Tailscale after
  provisioning, and a node missing from the tailnet MUST be (re-)enrolled.

### Key Entities

- **Node**: A physical host. Attributes: identity (`ragnaforge-dell` at 10.0.0.70 —
  data + compute; `ragnaforge-mac` at 10.0.0.71 — stateless compute), role, and
  target "ready Docker host" state. Its provisioning starting state is a freshly
  installed Debian OS reachable over SSH.
- **One-Time Migration Runbook**: The documented, non-automated procedure (in
  `docs/`) covering data preservation, verification, OS reinstall (which removes
  the incumbent k3s), and post-provision restore — for the current two machines
  only. Explicitly separate from the reusable provisioning.
- **Preserved Data Set**: The irreplaceable artifacts captured before reinstall —
  the media/photo snapshot plus each exported app configuration — each with a
  verification status.
- **Provisioning Definition**: The reproducible recipe (the single command and the
  tasks it runs) that brings a freshly installed node to the ready Docker host
  state; the source of truth for how a host is built.
- **Shared Storage**: The Dell's NFS export and the Mac's mount of it — the single
  media/config namespace both nodes see.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of identified irreplaceable data (media, photos, and the listed
  app configs) has a verified restorable copy before any destructive step — **zero
  data loss** across the migration.
- **SC-002**: A single command brings a freshly installed node to a ready Docker
  host with **zero** required manual follow-up steps and **zero** manual
  pre-cleanup.
- **SC-003**: Re-running provisioning on an already-provisioned node results in
  **zero** changes applied (idempotent).
- **SC-004**: Both nodes successfully run a test container after provisioning.
- **SC-005**: The Mac can read and write the Dell's shared storage over NFS.
- **SC-006**: **Zero** k3s components remain on either node after the one-time
  migration.
- **SC-007**: Both nodes are reachable over Tailscale after provisioning.
- **SC-008**: The reproducible provisioning contains **zero** one-time migration
  steps — it runs successfully against a fresh OS with no embedded preservation,
  teardown, or reinstall logic.
- **SC-009**: A competent operator can reproduce the full provisioning from the
  repository, and perform the one-time migration from the runbook, with no
  undocumented manual steps.

## Assumptions

- **Two separated concerns** (per Clarifications): the repo's provisioning targets
  a **freshly installed Debian OS with SSH enabled** and produces a ready Docker
  host; the one-time migration (preserve → reinstall → restore, which also removes
  the incumbent k3s) is a **documented runbook in `docs/`**, not automation, and
  applies only to the two current machines.
- **The Dell is the only stateful node**: per the "stateful → Dell" golden rule,
  all irreplaceable data belongs to `ragnaforge-dell`; data is preserved off-box
  and restored back to the Dell. `ragnaforge-mac` is stateless — nothing on it
  needs preserving.
- **Fresh OS install removes k3s**: no separate teardown automation is required;
  reinstalling the OS clears the incumbent cluster.
- **Tailscale on a fresh OS**: since the OS is reinstalled, Tailscale is
  (re)installed/enrolled as part of bringing each node online; provisioning/verify
  confirms reachability. (Supersedes the earlier "already installed" assumption.)
- **Preservation destination**: preserved artifacts go to storage independent of
  the machine being reinstalled (e.g. an external drive or the operator's
  workstation) with enough capacity for the ~103 GB set; the exact destination is
  an operator choice recorded in the runbook.
- **Provisioning tooling**: **Ansible** (lean, agentless, idempotent), confirmed
  after evaluating modern alternatives (pyinfra, NixOS) — see Clarifications. The
  exact task breakdown is an implementation detail for the planning phase.
- **Network facts hold**: LAN `10.0.0.0/24`, node LAN IPs as above, operator has
  physical/SSH access to both laptops.
- **Secrets** needed for provisioning follow the Phase 0 `.mise.toml` pattern
  (placeholder example tracked, real values gitignored).

## Dependencies

- **Phase 0 (repo scaffolding)** complete: repository layout, conventions, and the
  secret-handling pattern are in place.
- Operator can **freshly install Debian with SSH enabled** on both machines — the
  provisioning starting state.
- A preservation destination with sufficient capacity is available before the
  migration begins.
