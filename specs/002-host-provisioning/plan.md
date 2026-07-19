# Implementation Plan: Phase 1 — Migration & Host Provisioning

**Branch**: `002-host-provisioning` | **Date**: 2026-07-18 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-host-provisioning/spec.md`

## Summary

Deliver two things that the spec deliberately keeps separate:

1. **Reusable provisioning** — a lean Ansible playbook, invoked by `make provision`,
   that takes a **freshly installed Debian host reachable over SSH** to a ready
   Docker host: Docker Engine, NFS (Dell exports `/srv/nfs`, the Mac mounts it),
   `ip_forward` for the future VPN subnet router, a hardened admin/SSH baseline,
   and Tailscale enrolled. It is idempotent, per-node runnable, and secret-free
   (secrets injected from the gitignored `.mise.toml` via `mise`).
2. **A one-time migration runbook** — `docs/runbooks/phase1-migration.md` — that
   documents (not automates) preserving the ~103 GB media/photos + app configs,
   verifying restorability, reinstalling the OS (which removes the incumbent k3s),
   running `make provision`, and restoring the data.

Technical approach: a small, transparent set of native Ansible tasks (no
heavyweight role tree), official upstream apt repositories for Docker and
Tailscale, a systemd-automount NFS client so a missing server never wedges the
Mac, and a Makefile that wraps `mise exec -- ansible-playbook`. Correctness is
verified by re-running for idempotency, launching a test container, an NFS
read/write, and a grep proving no one-time migration logic leaked into the
automation.

## Technical Context

**Language/Version**: No application language. Infrastructure-as-config: Ansible
(YAML playbooks) targeting Debian 12 (bookworm) hosts, driven by a `make`
target. `mise` (from Phase 0) renders secrets into the environment.

**Primary Dependencies**: Ansible (control node, agentless over SSH); Docker
Engine + `nfs-kernel-server`/`nfs-common` + Tailscale installed on the hosts from
their official upstream apt repositories; `mise` for secret injection.

**Storage**: Dell exports `/srv/nfs` over NFS (media/config namespace); Docker
uses local named volumes. No database in this phase.

**Testing**: No unit-test suite. Verification is behavioral: a second playbook run
reports `changed=0` (idempotency), a test container runs on each node, the Mac
reads/writes the Dell's NFS export, `sysctl net.ipv4.ip_forward` reads `1`,
Tailscale reports both nodes up, and a `grep` confirms the automation contains no
preservation/teardown/reinstall steps. Captured in `quickstart.md`.

**Target Platform**: Two Intel laptops running freshly installed Debian 12 —
`ragnaforge-dell` (10.0.0.70, data + compute) and `ragnaforge-mac` (10.0.0.71,
stateless compute) — reachable over SSH on the LAN `10.0.0.0/24`.

**Project Type**: Infrastructure/documentation monorepo. Provisioning lives in
`provision/`; the one-time runbook lives in `docs/runbooks/`; the entry point is a
root `Makefile`.

**Performance Goals**: N/A (no runtime service). Practical goal: a full
`make provision` of a node completes in a few minutes over LAN and is safely
re-runnable.

**Constraints**: Lean — a handful of readable tasks, not the previous 7-role
tree (FR-014). Idempotent (FR-013). Provisioning assumes a fresh OS + SSH and
must contain **zero** one-time migration steps (FR-008, FR-016, SC-008). Each
node provisionable independently (FR-015). No real secret in any tracked file —
secrets come from `.mise.toml` via `mise` (Phase 0 pattern). Zero data loss
across the migration (SC-001).

**Scale/Scope**: 2 nodes; ~5 task groups (docker, nfs, sysctl, ssh-baseline,
tailscale); one static inventory; one Makefile; one migration runbook. Grows as
future nodes reuse the same playbook.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an unpopulated
template — no ratified principles or gates are defined, so there are no
constitution gates to evaluate.

Applied instead as guiding principles from the master plan's design north star:

- **Minimal custom code / off-the-shelf tools** — Ansible + upstream apt repos for
  Docker/Tailscale + stock NFS; no bespoke installers, no heavyweight role tree. ✅
- **Nothing silently goes outdated** — official upstream repositories; versions
  are visible and updated deliberately, not via blind `:latest`. ✅
- **Reproducible by a competent friend** — one command (`make provision`) against a
  fresh OS, plus a documented one-time migration runbook. ✅
- **Secrets never leak** — Tailscale auth key and any credentials injected from the
  gitignored `.mise.toml`; nothing real is tracked. ✅

**Result**: PASS (no violations; Complexity Tracking not required).

**Post-design re-check**: PASS — the design keeps provisioning lean and secret-free
and confines all one-time, irreversible steps to the documented runbook, matching
the spec's separation of concerns. No new violations introduced.

## Project Structure

### Documentation (this feature)

```text
specs/002-host-provisioning/
├── plan.md              # This file (/speckit-plan output)
├── spec.md              # Feature specification (clarified)
├── research.md          # Phase 0 output — decisions & rationale
├── data-model.md        # Phase 1 output — artifacts & required content
├── quickstart.md        # Phase 1 output — validation scenarios
├── contracts/           # Phase 1 output
│   ├── provisioning-contract.md    # `make provision` interface + "ready host" definition
│   └── migration-runbook-contract.md  # required runbook steps + zero-data-loss guarantee
├── checklists/
│   └── requirements.md  # Spec quality checklist (clarify output)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
homeserve/
├── Makefile                       # NEW: `make provision` (+ per-node, + check) entry point
├── provision/                     # Ansible (dir + README exist from Phase 0)
│   ├── README.md                  # exists
│   ├── inventory.yml              # NEW: ragnaforge-dell, ragnaforge-mac
│   ├── playbook.yml               # NEW: applies the task groups per host role
│   ├── group_vars/
│   │   └── all.yml                # NEW: non-secret vars (admin user, SSH public key, NFS paths)
│   └── tasks/                     # NEW: lean, readable task files
│       ├── docker.yml             #   Docker Engine via official apt repo
│       ├── nfs-server.yml         #   Dell: nfs-kernel-server + export /srv/nfs
│       ├── nfs-client.yml         #   Mac: nfs-common + systemd-automount mount
│       ├── sysctl.yml             #   ip_forward drop-in (Dell / router node)
│       ├── ssh-baseline.yml       #   admin user + authorized key + sshd hardening
│       └── tailscale.yml          #   install + enroll (idempotent) via TAILSCALE_AUTHKEY
├── docs/
│   └── runbooks/
│       └── phase1-migration.md    # NEW: one-time preserve → reinstall → restore runbook
└── .mise.toml.example             # exists — TAILSCALE_AUTHKEY already present; no new secret needed
```

**Structure Decision**: Keep the Phase-0 `provision/` directory and fill it with a
single flat playbook plus per-concern task files (not roles) to honor the "lean, a
handful of tasks" constraint. Host role differences (Dell = NFS server + router;
Mac = NFS client) are handled by including the appropriate task files per host in
`playbook.yml`, driven by inventory groups. The one-time migration is documentation
only, under `docs/runbooks/`, and never referenced by the playbook. `make provision`
at the repo root wraps `mise exec -- ansible-playbook` so secrets stay in the
gitignored `.mise.toml`.

## Complexity Tracking

No constitution violations. This section intentionally left empty.
