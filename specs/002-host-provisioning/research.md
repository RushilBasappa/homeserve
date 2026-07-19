# Phase 1 Research: Migration & Host Provisioning

The spec was fully clarified (see its `## Clarifications`), so no `NEEDS
CLARIFICATION` markers remained. This document records the design decisions that
shape the provisioning and the one-time migration runbook, so the tasks phase
inherits settled choices.

## R1 — Provisioning tool & shape

- **Decision**: A single flat **Ansible** playbook (`provision/playbook.yml`) that
  includes per-concern task files (`tasks/docker.yml`, `nfs-*.yml`, `sysctl.yml`,
  `ssh-baseline.yml`, `tailscale.yml`). No role tree, no `roles/`.
- **Rationale**: Ansible is agentless (SSH only — matches "fresh OS + SSH"),
  idempotent by design, and the master plan's chosen provisioner. Flat task files
  keep it "a handful of tasks, not the old 7 roles" (FR-014) while staying readable.
- **Alternatives considered**: Shell scripts (not idempotent, no change reporting —
  rejected); the previous 7-role structure (too heavy — explicitly retired);
  cloud-init (runs only at first boot, not re-runnable for existing/added nodes).

## R2 — Inventory & connection

- **Decision**: A static `provision/inventory.yml` with two hosts and two groups —
  `dell` (10.0.0.70) and `mac` (10.0.0.71) — plus a `docker_hosts` parent group.
  Tasks that need root use `become: true`. Connection user + SSH key come from
  `group_vars/all.yml` (non-secret) / the operator's SSH agent.
- **Rationale**: Two fixed LAN hosts don't warrant dynamic inventory. Groups let
  the playbook apply role-specific task files (NFS server vs client).
- **Alternatives considered**: Dynamic/cloud inventory (no cloud here); a single
  ungrouped host list (can't express the Dell/Mac role split cleanly).

## R3 — Docker Engine install

- **Decision**: Install Docker Engine from **Docker's official apt repository**
  via native Ansible tasks (add GPG key + repo, `apt` install
  `docker-ce`/`docker-ce-cli`/`containerd.io`/`docker-compose-plugin`, enable the
  service, add the admin user to the `docker` group).
- **Rationale**: Official repo is the upstream-supported path, transparent, and
  avoids a third-party Galaxy role that could silently drift (north star: nothing
  silently outdated). Compose plugin is included because every later phase is
  Compose-based.
- **Alternatives considered**: `get.docker.com` convenience script (not idempotent,
  discouraged for production); `geerlingguy.docker` Galaxy role (fine, off-the-shelf,
  but adds an external dependency + `requirements.yml` — not worth it for ~6 tasks);
  distro `docker.io` package (older, less predictable versions).

## R4 — NFS server & client

- **Decision**: Dell runs `nfs-kernel-server` exporting `/srv/nfs` to the Mac's LAN
  IP (`10.0.0.71`) with sane options (`rw,sync,no_subtree_check`). The Mac
  (`nfs-common`) mounts it via **systemd automount** (`noauto,x-systemd.automount,
  x-systemd.mount-timeout=…`) rather than a hard fstab mount.
- **Rationale**: systemd automount mounts on first access and does **not** block
  boot if the server is temporarily down — directly satisfying the "shared storage
  unavailable at Mac boot" edge case. Exporting to the specific client IP is
  least-privilege.
- **Alternatives considered**: Hard `fstab` mount (boot hangs if the Dell is
  offline — rejected); `autofs` (another daemon to manage — heavier than systemd
  automount which is already present); exporting to the whole `/24` (looser than
  needed now, can widen later).

## R5 — Kernel IP forwarding

- **Decision**: Enable `net.ipv4.ip_forward=1` via a persisted drop-in
  (`/etc/sysctl.d/99-ragnaforge.conf`) applied on the **Dell** (the future VPN
  subnet router). Applied idempotently with the `ansible.posix.sysctl` module.
- **Rationale**: The Dell is the wg-easy endpoint/subnet router (Phase 7); enabling
  forwarding now is harmless and keeps the host "VPN-ready." A drop-in survives
  reboots and package updates.
- **Alternatives considered**: Editing `/etc/sysctl.conf` directly (drop-ins are
  cleaner and less collision-prone); enabling on both nodes (harmless but the Mac
  isn't a router — keep it scoped to where it's needed).

## R6 — Admin user & SSH baseline

- **Decision**: Ensure an `admin` user exists with the operator's **public** SSH
  key (a non-secret var in `group_vars/all.yml`), in the `sudo` and `docker`
  groups; harden `sshd` via a drop-in (`PasswordAuthentication no`,
  `PermitRootLogin no`, `PubkeyAuthentication yes`) and reload the service.
- **Rationale**: A consistent admin/SSH baseline (FR-012) makes every node
  identical and key-only. SSH **public** keys are not secrets, so they live in a
  tracked var file — no `.mise.toml` entry needed.
- **Alternatives considered**: Storing the key in `.mise.toml` (unnecessary — it's
  public); rewriting the whole `sshd_config` (a drop-in is safer and upgrade-proof).

## R7 — Tailscale install & enrollment

- **Decision**: Install Tailscale from its **official apt repository** and enroll
  the node idempotently: run `tailscale up` with `--authkey` from
  `TAILSCALE_AUTHKEY` **only when** `tailscale status` shows the node is not already
  connected. Then verify reachability.
- **Rationale**: A freshly installed OS has no Tailscale, so the fresh-OS reality
  (spec Assumptions) means we must (re)install and enroll — but guarding on current
  status keeps it idempotent (FR-017/FR-013) and avoids re-authenticating a healthy
  node. The auth key is a real secret → injected from `.mise.toml` (already present
  in `.mise.toml.example` from Phase 0).
- **Alternatives considered**: Leaving Tailscale entirely manual per the master
  plan's original "already installed / verify" note (no longer true on a fresh OS —
  would break reproducibility); embedding the auth key in a tracked file (leaks a
  secret — rejected).

## R8 — Secret injection

- **Decision**: `make provision` runs `mise exec -- ansible-playbook …`; the
  playbook reads secrets from the env with `lookup('env', …)`. No secret is ever
  written to a tracked file; `.mise.toml` stays gitignored (Phase 0). As-built
  there are **two** env-injected secrets: `TAILSCALE_AUTHKEY` (enrollment) and
  `ANSIBLE_BECOME_PASSWORD` — the admin user's sudo password, referenced by
  `ansible_become_password` in `group_vars/all.yml` so escalation is
  non-interactive and the value never lands on a command line/process list.
- **Rationale**: Reuses the Phase 0 secret pattern end-to-end; keeps the repo safe
  to share. The nodes' admin user has password (not passwordless) sudo, so the
  become password is required for a one-command run (Cloudflare/WireGuard secrets
  belong to later phases).
- **Alternatives considered**: `ansible-vault` (introduces a second secret store —
  the plan standardized on `mise`); passing secrets on the CLI (leaks into shell
  history/process list).

## R9 — Idempotency & verification strategy

- **Decision**: Treat "run twice, second run reports `changed=0`" as the
  idempotency acceptance check; optionally `ansible-playbook --check` for a dry run.
  Post-provision checks: `docker run --rm hello-world` per node; NFS read/write from
  the Mac; `sysctl net.ipv4.ip_forward`; `tailscale status`; and a `grep` over
  `provision/` proving no preservation/teardown/reinstall keywords appear.
- **Rationale**: No app to unit-test; behavioral checks prove the "ready Docker
  host" state (SC-002..SC-008) directly and cheaply.
- **Alternatives considered**: Molecule + containers for role testing (overkill for
  a flat 5-task playbook on 2 known hosts); no verification (fails the reproducible/
  zero-surprise goal).

## R10 — One-time migration runbook

- **Decision**: A single `docs/runbooks/phase1-migration.md` covering, in order:
  (1) **preserve** — snapshot `/srv/nfs` (media + Immich, including a Postgres dump
  for Immich and a Vaultwarden data export) and export Actual/HA/*arr configs to an
  **external** destination; (2) **verify** — integrity check + one test restore;
  (3) **reinstall** — fresh Debian with SSH enabled (this removes k3s); (4)
  **provision** — `make provision`; (5) **restore** — copy preserved data back to
  the Dell. Includes an explicit "do not proceed past verification failure" gate.
- **Rationale**: Confines all one-time, irreversible steps to documentation
  (Clarifications Q1/Q2), keeps the automation clean (SC-008), and preserves the
  zero-data-loss guarantee (SC-001) with a verify-before-destroy ordering.
- **Alternatives considered**: Automating preservation/teardown in Ansible
  (rejected by clarification — one-time work shouldn't live in reusable automation);
  leaving it undocumented (loses the steps, risks data loss — rejected).

## R11 — Entry point (`make provision`)

- **Decision**: A root `Makefile` with `provision` (both nodes), `provision-dell`,
  `provision-mac` (per-node, satisfying independent provisioning FR-015), and
  `check` (dry run). Each target wraps `mise exec -- ansible-playbook -i
  provision/inventory.yml provision/playbook.yml [--limit <host>] [--check]`.
- **Rationale**: One memorable command (SC-002/SC-009); per-node limits let one
  unreachable node not block the other; `mise exec` guarantees secrets are present.
- **Alternatives considered**: Invoking `ansible-playbook` directly (loses the
  secret-injection wrapper and the memorable interface); a shell wrapper script
  (a Makefile is the conventional, discoverable entry point).

## Assumptions carried into design

- Debian on both nodes (as-built: **13 "trixie"**, system `python3.13`; the
  playbook avoids version-specific hacks so 12 "bookworm" also works).
- The operator installs the OS with SSH enabled and their key authorized (or
  password for the very first connection, immediately replaced by key-only).
- The Dell's `/srv/nfs` path is recreated on the fresh OS and repopulated by the
  runbook's restore step.
