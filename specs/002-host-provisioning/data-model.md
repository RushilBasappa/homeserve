# Phase 1 Data Model: Migration & Host Provisioning

This phase has no runtime data store. The "entities" are the provisioning
artifacts, the hosts they configure, and the migration runbook — each mapped to
the functional requirements in `spec.md`.

## Entity: Node

A physical host brought to the "ready Docker host" state by provisioning.

| Field | Value / required content | Source FR |
|---|---|---|
| Identity | `ragnaforge-dell` (10.0.0.70), `ragnaforge-mac` (10.0.0.71) | — |
| Role | Dell = data + compute (NFS server, subnet router); Mac = stateless compute | — |
| Starting state | Freshly installed Debian 12, reachable over SSH | FR-008 |
| Target state | Docker running · NFS (export or mount) · `ip_forward=1` (Dell) · admin/SSH baseline · Tailscale up | FR-009..FR-012, FR-017 |

**Validation rules**:
- Each node MUST reach the target state from a fresh OS with a single command and
  no manual follow-up. (FR-007, SC-002)
- Each node MUST be provisionable independently (`--limit`). (FR-015)

## Entity: Provisioning Definition

The reusable Ansible recipe plus its `make` entry point — the source of truth for
how a host is built.

| Field | Required content | Source FR |
|---|---|---|
| `inventory.yml` | `dell`, `mac` hosts + `docker_hosts` group | FR-007, FR-015 |
| `playbook.yml` | Includes per-concern task files by host role | FR-007 |
| `tasks/docker.yml` | Docker Engine from official apt repo, service enabled | FR-009 |
| `tasks/nfs-server.yml` | Dell: `nfs-kernel-server`, export `/srv/nfs` → Mac | FR-010 |
| `tasks/nfs-client.yml` | Mac: `nfs-common`, systemd-automount mount | FR-010 |
| `tasks/sysctl.yml` | `net.ipv4.ip_forward=1` drop-in (Dell) | FR-011 |
| `tasks/ssh-baseline.yml` | admin user + authorized key + sshd hardening | FR-012 |
| `tasks/tailscale.yml` | install + idempotent enroll via `TAILSCALE_AUTHKEY` | FR-017 |
| `group_vars/all.yml` | Non-secret vars (admin user, SSH public key, NFS paths) | FR-012 |
| `Makefile` | `provision`, `provision-dell`, `provision-mac`, `check` | FR-007, FR-015 |

**Validation rules**:
- MUST be idempotent — a second run reports `changed=0`. (FR-013, SC-003)
- MUST remain lean (flat task files, no role tree). (FR-014)
- MUST contain **zero** one-time migration steps — no preservation, k3s teardown,
  or OS reinstall logic anywhere under `provision/` or in the `Makefile`.
  (FR-016, SC-008)
- MUST reference secrets only via `mise`-rendered env; no real secret tracked.

## Entity: Shared Storage

The single media/config namespace both nodes see.

| Field | Required content | Source FR |
|---|---|---|
| Export (Dell) | `/srv/nfs` exported `rw,sync,no_subtree_check` to 10.0.0.71 | FR-010 |
| Ownership (Dell) | Export dir owned by `admin_user` (mode `0775`) so the client can write under NFS `root_squash` | FR-010, SC-005 |
| Mount (Mac) | `/srv/nfs` via `x-systemd.automount` (`boot: false` to match `noauto`) | FR-010 |

**Validation rules**:
- The Mac MUST be able to read and write the export. (SC-005) — requires the
  export dir be owned by a non-root user the client maps to (root is squashed).
- A temporarily-absent server MUST NOT wedge the Mac's boot. (edge case)
- The client mountpoint task MUST NOT enforce a mode (once mounted, the path is
  the server-owned NFS root and a chmod would fail).

## Entity: One-Time Migration Runbook

The documented, non-automated procedure for the two current machines.

| Field | Required content | Source FR |
|---|---|---|
| Preserve | Snapshot `/srv/nfs` (media + Immich, incl. Postgres dump); export Vaultwarden, Actual, HA, *arr configs; to an external destination | FR-001, FR-002, FR-003 |
| Verify | Integrity check + ≥1 test restore before any destructive step | FR-004 |
| Gate | Explicit "stop if verification fails" before wipe/reinstall | FR-004, FR-005 |
| Reinstall | Fresh Debian + SSH (removes incumbent k3s) | FR-006 |
| Provision | Run `make provision` on the fresh OS | FR-007 |
| Restore | Copy preserved data back to the Dell | FR-005 |

**Validation rules**:
- Steps MUST be ordered so verification precedes any destructive action.
  (FR-005, SC-001)
- k3s removal MUST appear only here, never in the automation. (FR-006, SC-008)
- Following it MUST achieve zero data loss and zero remaining k3s. (SC-001, SC-006)

## Entity: Preserved Data Set

The irreplaceable artifacts captured before reinstall (produced by the runbook,
not the automation).

| Field | Required content | Source FR |
|---|---|---|
| Media/photo snapshot | ~103 GB `/srv/nfs`, including Immich (with DB dump) | FR-001 |
| App config exports | Vaultwarden, Actual Budget, Home Assistant, *arr | FR-002 |
| Location | Independent of the machine being reinstalled | FR-003 |
| Verification status | Integrity pass + demonstrated test restore | FR-004 |

**Validation rules**:
- 100% of listed artifacts MUST have a verified restorable copy before teardown.
  (SC-001)
