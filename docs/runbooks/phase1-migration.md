# Runbook: Phase 1 — One-Time Migration

**This is documentation, not automation.** It is followed **once, by hand**, to
move the two current Ragnaforge machines onto a fresh OS without losing data. The
reusable path for future or added nodes is `make provision` alone — none of the
one-time steps below live in `provision/` or the `Makefile` (FR-016, SC-008).

> **Load-bearing guarantee — verify before you destroy.** No wipe or reinstall is
> reachable until preservation is complete **and** verified (steps 1–4). Do not
> skip the STOP gate.

The steps below are strictly ordered. Follow them top to bottom.

---

## 1. Preserve — capture everything irreplaceable (FR-001, FR-002)

Capture, from the current Dell:

- **Media & photos** — snapshot the full `/srv/nfs` namespace (~103 GB),
  including the **Immich** library. For Immich, also take a **Postgres dump** of
  its database so the library is restorable, not just the files on disk:

  ```sh
  # Immich database dump (adjust container/user/db names to your deployment):
  docker exec -t immich_postgres pg_dumpall -c -U postgres > immich-postgres.sql

  # Full media/config snapshot (preserves permissions):
  sudo tar -C /srv -czpf srv-nfs-snapshot.tar.gz nfs
  ```

- **App config exports** — export the configuration/state of each stateful app:
  - **Vaultwarden** — its data directory (includes `db.sqlite3`, `attachments/`,
    `sends/`, and `rsa_key*`). Treat as sensitive.
  - **Actual Budget** — its server data directory (the budget files + sync state).
  - **Home Assistant** — its `config/` directory (or a Settings → Backups archive).
  - **The \*arr apps** (Sonarr, Radarr, Prowlarr, etc.) — each app's config
    directory (contains `*.db` and `config.xml`).

Stop the relevant containers (or put apps into a consistent state) before copying
their databases so you capture a clean, non-torn copy.

## 2. Destination — write the preserved set off-box (FR-003)

Write **every** preserved artifact to storage **independent of the machine being
reinstalled** — an external drive or a separate workstation. Before copying,
**confirm the destination has capacity** for the full ~103 GB set plus the config
exports and the Immich dump. Nothing preserved may live only on the Dell that is
about to be wiped.

## 3. Verify — prove the copies are good (FR-004)

For every artifact:

- **Integrity-check** the copy (e.g. compare `sha256sum` of source vs.
  destination for the snapshot and each export; confirm the tarball lists and
  extracts without error: `tar -tzf srv-nfs-snapshot.tar.gz >/dev/null`).
- Perform **at least one test restore** — actually restore one representative
  artifact (e.g. extract a subtree of the media snapshot, or load the Immich
  Postgres dump into a throwaway database) and confirm it is usable. A copy that
  has never been restored is not a verified backup.

## 4. 🛑 STOP GATE — do not proceed until verification passes (FR-004, FR-005)

**Do not perform any destructive step (wipe, reinstall) until ALL of the following
are true:**

- [ ] The full `/srv/nfs` snapshot exists off-box and its checksum matches.
- [ ] The Immich Postgres dump exists off-box and restored cleanly in the test.
- [ ] Vaultwarden, Actual Budget, Home Assistant, and every \*arr config export
      exists off-box and passed its integrity check.
- [ ] The destination has confirmed capacity and all copies completed.
- [ ] At least one **test restore** succeeded.

If **any** box is unchecked, **STOP** and fix it. Everything below this line is
irreversible.

---

## 5. Reinstall — fresh Debian with SSH (FR-006)

> This is the **only** place the incumbent **k3s** cluster is removed. k3s
> teardown is **not** part of the reusable provisioning (SC-008) — it is a
> one-time step that returns the node to a clean starting state.

Reach the clean state one of two ways:

- **Fresh OS install (canonical):** freshly install **Debian** (13 "trixie"
  as-built; 12 "bookworm" also works). The reinstall wipes k3s and every trace of
  the old cluster.
- **In-place teardown (as-built alternative):** run `scripts/cleanup-all.sh --yes`
  from the control machine. It removes k3s (via its official uninstaller), Docker,
  the `/srv/nfs` data, and caches while **preserving SSH access** (host keys +
  `authorized_keys` + the openssh server) — so no reinstall is needed. Dry-run by
  default; requires typing `wipe <hostname>` to proceed.

Either way, during/after:

- Ensure the **SSH server** is up with the operator's public key authorized (a
  fresh install may need a password for the first connection, immediately replaced
  by key-only, which `make provision` enforces).
- Recreate the `/srv/nfs` path if absent (empty for now — repopulated in step 7).

Both paths remove k3s and leave a clean host; provisioning assumes exactly this
starting state and performs no cleanup of leftovers.

## 6. Provision — `make provision` (FR-007)

From the repo root, with a filled-in `.mise.toml` (`TAILSCALE_AUTHKEY` **and**
`ANSIBLE_BECOME_PASSWORD` — see the appendix):

```sh
make deps               # first time only — installs the ansible.posix collection
make provision          # both nodes — or `make provision-dell` for one
```

This brings the fresh host to the ready Docker host state: Docker, NFS
(export/mount), `ip_forward`, the admin/SSH baseline, and Tailscale. Verify with
the checks in
[`contracts/provisioning-contract.md`](../../specs/002-host-provisioning/contracts/provisioning-contract.md).

## 7. Restore — copy the preserved data back (FR-005)

Copy the preserved media/photos and app configs from the external destination
back onto the Dell:

```sh
sudo tar -C /srv -xzpf srv-nfs-snapshot.tar.gz     # restores /srv/nfs
# Restore the Immich Postgres dump into its fresh database, then start Immich.
# Restore each app's config directory to its Compose bind-mount path.
```

Confirm the restored data is **readable** (open Immich, unlock Vaultwarden, load
a budget, check Home Assistant history, confirm the \*arr libraries). Only once
everything reads back correctly is the migration complete — zero data loss
(SC-001), zero remaining k3s (SC-006).

---

## Appendix — Phase 1 implementation notes (as-built)

Context the design docs don't capture: decisions and gotchas found while running
`make provision` against the real Dell and Mac. Recorded so the next person (or
future me) isn't surprised.

### Environment as-built

- **OS:** Debian **13 "trixie"** on both nodes (system `python3.13`). The playbook
  avoids version-specific hacks, so 12 "bookworm" also works.
- **Connection / admin:** single account — the operator's own `rushil`. Ansible
  connects as `rushil` over the existing `~/.ssh/ragnaforge-cluster` key
  (referenced by path in `group_vars/all.yml`; only the public half is committed).
  There is **no separate `admin` account**; `admin_user: rushil`.
- **Nodes:** `ragnaforge-dell` 10.0.0.70 (NFS server + subnet router),
  `ragnaforge-mac` 10.0.0.71 (stateless NFS client).

### Secrets (both from the gitignored `.mise.toml`, injected via `mise`)

- `TAILSCALE_AUTHKEY` — Tailscale enrollment.
- `ANSIBLE_BECOME_PASSWORD` — the nodes have **password** sudo (not passwordless),
  so this is required for `make provision` to escalate non-interactively. It's read
  by `ansible_become_password` via an env lookup — never on a command line.
- Run `mise trust` once in the repo, or `mise` won't render `[env]` (this silently
  yields an empty auth key / "Missing sudo password").

### Reaching the clean starting state

- These boxes were wiped **in place** with `scripts/cleanup-all.sh --yes` rather
  than reinstalled (step 5, in-place option). It removes k3s (official uninstaller),
  Docker, `/srv/nfs` data, and caches while keeping SSH. Freed ~140 GB → ~2 GB on
  the Dell.

### Gotchas fixed during bring-up (already reflected in `provision/`)

- **Stale `/etc/exports`:** the old k3s NFS server left exports for
  `/srv/nfs/{media,shared,photos}`; after the data wipe those paths were gone and
  `exportfs -ra` failed. The in-place cleanup empties `/srv/nfs` but does **not**
  touch `/etc/exports` — clear stale export lines by hand (or on a fresh install
  this can't happen).
- **NFS didn't mount without a reboot:** `ansible.posix.mount state=present` only
  writes `/etc/fstab`; the client task now also reloads systemd and enables the
  `srv-nfs.automount` unit so it's active immediately.
- **Mac couldn't write the export:** `/srv/nfs` was `nobody:nogroup`; under
  `root_squash` a client can't write. The server task now owns it `rushil:rushil`
  `0775`. (`rushil` is uid 1000 on both nodes, so the mapping lines up.)
- **Non-idempotent mountpoint:** once mounted, `/srv/nfs` on the Mac is the
  server-owned NFS root, so enforcing a mode chmod'd it and failed — the mountpoint
  task no longer sets a mode; `boot: false` matches `noauto`.

### Config / warnings

- `ansible.cfg` (repo root, auto-loaded): `interpreter_python = auto_silent`
  (quiets the remote system-python discovery warning) and
  `deprecation_warnings = False` (silences `ansible.posix` internal deprecations;
  our own tasks are clean — rely on `ansible-lint` to catch new ones).
- Collections are declared in `provision/requirements.yml` and installed by
  `make deps` (the `provision*` targets depend on it).

### Verified end state (both nodes)

`make provision` twice → `changed=0` (idempotent) · `docker run --rm hello-world`
runs (rootless — `rushil` is in the `docker` group) · Mac reads **and writes**
`/srv/nfs` over NFS · `ip_forward=1` on the Dell · `sshd`: password & root login
disabled · Tailscale up, each node sees the other.
