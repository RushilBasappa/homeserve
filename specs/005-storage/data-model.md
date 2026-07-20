# Phase 1 Data Model: Storage

There is no application data model. The "entities" here are the physical/logical
storage objects the phase makes real, and the invariants that keep them correct.

## Entity: Shared media namespace

The single tree exported by the Dell and mounted on the Mac — the one place both
nodes and all future media apps read/write shared media.

| Attribute | Value |
|---|---|
| Root path | `/srv/nfs` |
| Server | `ragnaforge-dell` (10.0.0.70) — owns the real bytes |
| Client | `ragnaforge-mac` (10.0.0.71) — sole permitted mount (export pinned to its IP) |
| Transport | NFS (from Phase 1); Mac mounts via `systemd` automount (`noauto,x-systemd.automount`) |
| Owner | `1000:1000` (the `rushil` account) |
| Dir mode | `2775` (group-writable + **setgid**) |

**Invariants**
- Same path resolves to the same bytes on both nodes (one consistent view).
- The Mac mount activates **on demand** and never blocks boot when the server is down.
- **No app config** lives under this root (config → local named volumes on the Dell).

## Entity: Standard directory layout

The agreed subtree that Phase 5/6 stacks mount by known path (the **contract** —
see `contracts/media-layout.md`).

```text
/srv/nfs/
├── media/
│   ├── movies/        # Radarr library · Jellyfin movies (P5)
│   └── tv/            # Sonarr library · Jellyfin shows (P5)
├── downloads/
│   ├── complete/      # qBittorrent finished → servarr import (hardlink) (P5)
│   └── incomplete/    # qBittorrent in-progress (P5)
└── photos/            # Immich external-library / originals namespace (P6)
```

**Invariants**
- `media/` and `downloads/` share **one filesystem** → import = instant hardlink /
  atomic rename (never a cross-device copy).
- Every directory carries the shared owner + `2775` setgid, so a file any app writes
  is readable/writable by the others.
- The set is **minimal**; new top-level namespaces (`music/`, `books/`, …) are added
  only by the phase whose stack needs them.

## Entity: Growth-path runbook

The document describing how capacity is added without touching the export path.

| Attribute | Value |
|---|---|
| Location | `docs/runbooks/phase4-storage.md` |
| Mechanism | mergerfs union of internal disk + USB disk(s), pooled at/under `/srv/nfs` |
| Key invariant | Adding capacity leaves `/srv/nfs` — and therefore every app mount — unchanged |
| Referenced by | `docs/CONVENTIONS.md` ("documented in Phase 4") — must resolve, not dangle |

## Entity: Verification record

Evidence that the namespace works, so downstream phases build on proof, not assumption.

| Attribute | Value |
|---|---|
| Location | `docs/runbooks/phase4-storage.md` (verification section) |
| Contents | cross-node write/read result; on-demand automount result; server-down boot result; Mac stateful-data audit result |
| Maps to | SC-001, SC-002, SC-005; FR-007, FR-008 |

## State transitions

None. Directories are created once (idempotently) and thereafter only filled by
later-phase apps. The namespace has no lifecycle beyond "provisioned → in use".
