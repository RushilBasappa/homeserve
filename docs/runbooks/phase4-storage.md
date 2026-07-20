# Runbook — Phase 4: Storage

Make the shared storage namespace **real, verified, and documented** — without
building a new storage system. The NFS *mechanism* already ships in Phase 1
(`provision/tasks/nfs-server.yml` exports `/srv/nfs` from the Dell;
`provision/tasks/nfs-client.yml` automounts it on the Mac). This phase
materializes the standard media tree under that export, proves it behaves as one
consistent cross-node namespace, and writes down the capacity-growth path.

> **One-line flow:** Ansible creates `media/{movies,tv}` + `downloads/{complete,incomplete}` + `photos/`
> under `/srv/nfs` (owner `1000:1000`, `setgid 2775`) → prove write-on-Dell/read-on-Mac →
> confirm on-demand automount + server-down boot resilience → document mergerfs+USB growth.

## Prerequisites

- Phases 1–3 live: both nodes provisioned, NFS export + automount up.
- `ssh ragnaforge-dell` (10.0.0.70) and `ssh ragnaforge-mac` (10.0.0.71) work.
- The tree is provisioned by `provision/tasks/storage-layout.yml`, run on the Dell
  via `make provision-dell` (idempotent — a second pass reports `changed=0`).

---

## Standard layout

The concrete, hardlink-friendly tree Phase 5 (ARR + Jellyfin) and Phase 6 (Immich)
mount — see `specs/005-storage/contracts/media-layout.md` for the full contract.

```text
/srv/nfs/
├── media/
│   ├── movies/     # Radarr + Jellyfin
│   └── tv/         # Sonarr + Jellyfin
├── downloads/
│   ├── complete/   # qBittorrent → Radarr/Sonarr (hardlink source)
│   └── incomplete/ # qBittorrent in-progress
└── photos/         # Immich external-library / shared originals
```

Every directory is owned `1000:1000` (the `rushil` account) with mode `2775`
— the leading `2` is the **setgid** bit, so files any media app creates inherit the
shared group and stay mutually readable/writable (the precondition for cross-app
hardlinks). `media/` and `downloads/` live under **one root on one filesystem**, so
servarr imports are instant hardlinks/atomic renames, never cross-device copies.

**Check 1 evidence** — `ssh ragnaforge-dell 'ls -la … && stat -c "%n %U:%G %a" …'`
(SC-003, FR-003/FR-004):

```text
/srv/nfs:
drwxrwxr-x 5 rushil rushil 4096 downloads media photos
drwxrwsr-x 4 rushil rushil 4096 downloads   # setgid (s) present
drwxrwsr-x 4 rushil rushil 4096 media
drwxrwsr-x 2 rushil rushil 4096 photos

/srv/nfs/media:      movies/  tv/     (both drwxrwsr-x rushil rushil)
/srv/nfs/downloads:  complete/ incomplete/ (both drwxrwsr-x rushil rushil)

/srv/nfs/media/movies       rushil:rushil 2775
/srv/nfs/media/tv           rushil:rushil 2775
/srv/nfs/downloads/complete rushil:rushil 2775
/srv/nfs/downloads/incomplete rushil:rushil 2775
/srv/nfs/photos             rushil:rushil 2775
```

All five leaf paths exist, each `rushil:rushil 2775` with the setgid bit set
(`drwxrwsr-x`). ✅

---

## Verification evidence (SC-001..005)

Behavioral proof per `specs/005-storage/quickstart.md`. All six checks pass.

### Check 2 — Cross-node consistency (SC-001, FR-001) ✅

Write on the Dell, read on the Mac, append on the Mac, read back on the Dell:

```text
ssh ragnaforge-dell 'echo hello-from-dell > /srv/nfs/downloads/incomplete/_p4test'
ssh ragnaforge-mac  'cat …/_p4test'   → hello-from-dell            # Mac reads Dell's write
ssh ragnaforge-mac  'echo edited-on-mac >> …/_p4test'
ssh ragnaforge-dell 'cat …/_p4test'   → hello-from-dell            # Dell sees Mac's append
                                         edited-on-mac
ssh ragnaforge-dell 'rm …/_p4test'    # cleaned up
```

One consistent namespace; no manual mount step on the Mac.

### Check 3 — On-demand automount, no manual mount (SC-001, FR-002) ✅

```text
systemctl status srv-nfs.automount → active (running)
ls /srv/nfs/media                  → access OK (mount activated on demand)
findmnt /srv/nfs                   → /srv/nfs 10.0.0.70:/srv/nfs nfs4 rw,vers=4.2,hard,proto=tcp,…
```

The automount unit is active; first access triggers the real `nfs4` mount from
`10.0.0.70:/srv/nfs`.

### Check 4 — Server-down Mac boot does not wedge (SC-002, FR-002, edge case) ✅

Simulates "server absent at boot". Driven via Ansible ad-hoc (`-b`, reusing the
`mise`-rendered become password) so no sudo secret is handled by hand:

```text
[1] dell: systemctl stop nfs-server                          → stopped
[2] mac:  systemctl restart srv-nfs.automount (boot-equiv)   → returned promptly, NO hang
    mac:  systemctl is-active srv-nfs.automount              → active   (did not wedge)
[3] dell: systemctl start nfs-server                         → started
[4] mac:  ls /srv/nfs/media                                  → movies  tv  (recovered on access)
```

The automount comes up **without hanging** while the server is down (the
`noauto,x-systemd.automount` design); once the server returns, first access recovers
— no reboot loop, no manual mount.

### Check 6 — Growth-path runbook resolves (SC-004, FR-006) ✅

`docs/CONVENTIONS.md`'s "documented in Phase 4" mergerfs reference now links this
runbook (`docs/runbooks/phase4-storage.md#mergerfs--usb-growth-path`), whose growth
section states the export path — and every app mount — stays unchanged. One hop from
reference to invariant.

---

## Mac stateful-data audit

Upholds the golden rule (stateful → Dell) before Phase 5/6 land stateful stacks.

**Check 5 evidence** — `docker volume ls` + `docker ps` on the Mac (SC-005, FR-007):

```text
VOLUME NAME               container
komodo-periphery-root     bootstrap-periphery-1

docker inspect bootstrap-periphery-1 (mounts):
  volume komodo-periphery-root -> /etc/komodo
  bind   /var/run/docker.sock  -> /var/run/docker.sock
  bind   /proc                 -> /proc
```

**Result: clean, with one expected/justified exception.** The only volume/container
on the Mac is the **Komodo Periphery agent itself** — the management daemon that lets
Core deploy stacks to this node. `komodo-periphery-root → /etc/komodo` is the agent's
own working state (its stack-repo cache), not an application database or media config;
`docker.sock` and `/proc` are how it manages containers. **No app / database state
lives on the Mac** — Phases 1–3 kept all stateful data on the Dell, and the golden
rule holds heading into Phase 5/6.

---

## Mergerfs + USB growth path

**This is the "documented in Phase 4" reference from `docs/CONVENTIONS.md`.** It
describes — but does **not** build — the path for when the Dell's internal disk
(238 GB NVMe) fills. Nothing here is provisioned today; the NVMe has near-term
headroom (research R5). This is the known procedure for the future "disk full" moment.

### The invariant (why this is safe)

> **The export path `/srv/nfs` — and therefore every app mount — never changes when
> capacity is added.** Consumers (qBittorrent, Radarr/Sonarr, Jellyfin, Immich) keep
> the exact `contracts/media-layout.md` paths. Growth happens *underneath* the export,
> transparently.

### Why mergerfs (not LVM / ZFS / btrfs)

`mergerfs` is a FUSE union filesystem: it presents several underlying disks as **one**
directory tree, with **no striping and no parity**. Losing one disk loses only *that
disk's* files — the rest of the pool is untouched. That is ideal for growable, easily
re-acquired media. LVM grows a block device but a single lost disk can lose the whole
volume; ZFS/btrfs pools want more RAM/attention than this fleet warrants (research R5).

### Procedure (when the NVMe fills)

1. **Attach the USB disk**, partition + format it (e.g. `ext4`), and note its UUID
   (`lsblk -f`).
2. **Mount the two "branches" at internal paths** (NOT at `/srv/nfs`). Convention:
   - existing NVMe data → `/mnt/disk1`
   - new USB disk       → `/mnt/disk2`
   Move the current `/srv/nfs` contents onto `/mnt/disk1` (or keep the NVMe as disk1
   and add the USB as disk2 — either way both are *branches*, not the export).
3. **Install mergerfs** and union the branches **onto the export path**:
   ```text
   /mnt/disk*  →  /srv/nfs   (fuse.mergerfs)
   # /etc/fstab
   /mnt/disk1:/mnt/disk2  /srv/nfs  fuse.mergerfs \
     defaults,allow_other,use_ino,category.create=mfs,minfreespace=20G,fsname=mergerfs  0 0
   ```
   `category.create=mfs` writes new files to whichever branch has the most free space;
   `use_ino` keeps inode numbers stable so **hardlinks work within a branch** (keep a
   file's `downloads/` and `media/` copies on the same branch — mergerfs does this by
   default for same-directory creates, preserving the instant-import property).
4. **Re-export unchanged**: `/etc/exports` still exports `/srv/nfs` to the Mac — no
   edit. `exportfs -ra`. The Mac's automount, and every future container mount, is
   **identical**.
5. **Codify it** (matching this repo's north star): add a `provision/tasks/` task for
   the mounts + mergerfs fstab entry so a clean rebuild reproduces the pool, exactly
   as `storage-layout.yml` reproduces the tree today.

### What stays fixed

- The NFS export path `/srv/nfs` and its export options.
- The five `contracts/media-layout.md` paths and their `1000:1000 / 2775` ownership.
- Every consumer's mount and root-folder config in Phase 5/6.

Only the *physical backing* under `/srv/nfs` changes — from one disk to a pooled
union. That containment is the whole point.

<!-- SC-004, FR-006 -->
