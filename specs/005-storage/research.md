# Phase 0 Research: Storage

The mechanism (NFS export + automount) is settled in Phase 1. The open questions
for Phase 4 are about the **shape and ownership** of the shared tree and the
**growth path** — everything else is verification. Each decision below records what
was chosen, why, and what was rejected.

## R1 — One tree, not separate media/downloads mounts (hardlink safety)

- **Decision**: Put `downloads/` and `media/` under the **same** root
  (`/srv/nfs/downloads`, `/srv/nfs/media`) on the **same filesystem**, not on
  separate mounts/exports.
- **Rationale**: The servarr apps (Radarr/Sonarr, Phase 5) *import* completed
  downloads into the library. On one filesystem that import is an instant **hardlink
  or atomic rename**; across filesystems it becomes a slow, space-doubling copy and
  breaks seeding. The TRaSH-guides "one tree" layout is the well-trodden fix. Making
  this the shape now prevents a painful re-layout mid-Phase-5.
- **Alternatives rejected**: separate `media` and `downloads` exports (breaks
  hardlinks); per-app download folders scattered across volumes (same problem,
  harder to reason about).

## R2 — Concrete directory layout

- **Decision**:
  ```text
  /srv/nfs/
  ├── media/
  │   ├── movies/
  │   └── tv/
  ├── downloads/
  │   ├── complete/
  │   └── incomplete/
  └── photos/
  ```
- **Rationale**: Matches what `CONVENTIONS.md` already describes (media library +
  shared media namespace) and what Phase 5/6 will mount: `media/movies` +
  `media/tv` for Radarr/Sonarr + Jellyfin libraries; `downloads/complete` +
  `downloads/incomplete` for qBittorrent (behind Gluetun) with atomic-move on
  completion; `photos/` as an optional **external-library / originals** namespace for
  Immich. Kept intentionally minimal — `music/`, `books/`, etc. are added by a later
  phase only if a stack needs them (YAGNI).
- **Alternatives rejected**: a deeper pre-baked tree (`music`, `audiobooks`, `roms`…)
  — speculative; each unused dir is noise. Flat `movies`/`tv` at the root (no `media/`
  parent) — loses the clean `media` vs `downloads` split that makes the hardlink
  boundary obvious.

## R3 — Ownership & permissions (shared PUID/PGID + setgid)

- **Decision**: Own the whole tree `1000:1000` (the already-provisioned `rushil`
  account) and set directory mode **`2775`** — the `2` is the **setgid** bit so
  files/dirs created inside inherit the parent group. Every media app (qBittorrent,
  Radarr, Sonarr, Jellyfin, Immich) runs with `PUID=1000`/`PGID=1000`.
- **Rationale**: The apps run in separate containers but must read/write each other's
  files (download → import → play). A single shared UID/GID with group-writable +
  setgid dirs is the standard LinuxServer.io/servarr pattern and guarantees a file
  qBittorrent writes is importable by Radarr and readable by Jellyfin. `1000:1000`
  reuses the existing admin identity, so the operator's own shell can also manage the
  tree without `sudo`. NFS is **not** `root_squash`-hostile here because clients write
  as UID 1000 (a normal user), never root.
- **Alternatives rejected**: a dedicated `media` group with the apps in it — cleaner
  in theory but adds a group to provision and every app's PGID to track, for no
  benefit at this scale. Per-app UIDs with ACLs — overkill; ACLs over NFSv3 are
  fragile.

## R4 — Reproducible tree via Ansible, not a one-off mkdir

- **Decision**: Create the tree with a new idempotent task file
  `provision/tasks/storage-layout.yml`, included from `provision/playbook.yml` and
  run **on the Dell only** (the NFS server owns the real directories; the Mac sees
  them through the mount).
- **Rationale**: The project's north star is "reproducible from git / stand up on any
  device". A tree hand-`mkdir`'d over SSH evaporates on a clean rebuild; an Ansible
  `file`-loop with `state: directory` + `recurse` is idempotent and self-documenting,
  matching how `nfs-server.yml` already provisions `/srv/nfs`.
- **Alternatives rejected**: documenting the `mkdir` commands in a runbook for the
  operator to paste — not reproducible, drifts from reality.

## R5 — Growth path: mergerfs + USB, export path unchanged

- **Decision**: Document (do **not** build) the growth path: when the internal disk
  fills, add a USB disk and pool it *under* `/srv/nfs` with **mergerfs**, so the NFS
  export path and every app mount stay identical. Written as
  `docs/runbooks/phase4-storage.md`, resolving the "documented in Phase 4" reference
  already in `CONVENTIONS.md`.
- **Rationale**: mergerfs unions multiple disks into one directory tree without
  striping/parity risk — ideal for growable media where losing one disk loses only
  that disk's files. Keeping the union *at or below the export path* means consumers
  never reconfigure. Documenting-not-building matches the spec's small scope; the
  238 GB NVMe has near-term headroom.
- **Alternatives rejected**: LVM (grows a block device but rigid, and a single lost
  disk can lose the whole volume); ZFS/btrfs pools (heavier, more RAM/attention than a
  7.5 GB laptop warrants); building mergerfs now (out of scope, no capacity need yet).

## R6 — Verification is a first-class deliverable

- **Decision**: Treat "storage works" as something **proven and recorded**, not
  assumed. `quickstart.md` defines the cross-node write/read test, the on-demand
  automount check, and the server-down boot-resilience check; the results are pasted
  into `docs/runbooks/phase4-storage.md` (FR-008).
- **Rationale**: Phase 5/6 are expensive to debug if storage silently misbehaves.
  Catching a mount/permission problem now, against an empty tree, is far cheaper.
- **Alternatives rejected**: trusting the Phase-1 playbook ran cleanly — a green
  Ansible run proves *configuration applied*, not *cross-node semantics correct*.

## R7 — Mac stateful-data audit

- **Decision**: A quick, recorded audit that no stateful app data currently lives on
  the Mac (Docker named volumes / bind mounts holding databases or config), upholding
  the golden rule before Phase 5/6 land stateful stacks.
- **Rationale**: Cheap insurance; the rule is only real if checked. Result (expected:
  clean, since Phases 1–3 kept all state on the Dell) is recorded, with any exception
  justified.
- **Alternatives rejected**: skipping it — leaves the golden rule as an unverified
  claim exactly when stateful stacks are about to arrive.
