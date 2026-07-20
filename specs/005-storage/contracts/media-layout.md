# Contract: Media Layout

This is the interface Phase 4 exposes to later phases. Phase 5 (ARR + Jellyfin) and
Phase 6 (Immich) **mount these exact paths**; Phase 4's job is to guarantee they
exist with the ownership below. Changing a path here is a breaking change for those
phases.

## Paths (server truth on the Dell; identical on the Mac via mount)

| Path | Consumer(s) | Purpose |
|---|---|---|
| `/srv/nfs/media/movies` | Radarr, Jellyfin | Movie library (final, imported) |
| `/srv/nfs/media/tv` | Sonarr, Jellyfin | TV library (final, imported) |
| `/srv/nfs/downloads/complete` | qBittorrent → Radarr/Sonarr | Finished downloads awaiting import (hardlink source) |
| `/srv/nfs/downloads/incomplete` | qBittorrent | In-progress downloads |
| `/srv/nfs/photos` | Immich | External-library / shared originals namespace (optional per Immich config) |

## Guarantees

1. **Existence**: every path above exists after `provision/playbook.yml` runs (created
   idempotently by `provision/tasks/storage-layout.yml`).
2. **Same filesystem**: `media/` and `downloads/` are under one root on one
   filesystem → import is a hardlink/atomic-rename, never a cross-device copy. Phase 5
   MUST keep qBittorrent's download path and the servarr root folders inside this tree
   to preserve that.
3. **Ownership**: owned `1000:1000`, dir mode `2775` (setgid). Consumers MUST run with
   `PUID=1000` / `PGID=1000` so files they create stay mutually readable/writable.
4. **Stability under growth**: capacity added later (mergerfs + USB) appears *under*
   these paths; the paths themselves never change.

## Consumer obligations (later phases)

- Run media containers with `PUID=1000`, `PGID=1000`.
- Mount the tree read-write where import/write is needed (qBittorrent, servarr) and
  read-only where only playback is needed (Jellyfin libraries MAY be `:ro`).
- Do **not** place app config/state under `/srv/nfs` — config goes to a local named
  volume on the Dell (per `docs/CONVENTIONS.md`).
- If a new top-level namespace is needed (e.g. `music/`), add it in that phase's
  provisioning, following the same ownership/setgid rule — do not assume it pre-exists.

## Non-guarantees

- Phase 4 does **not** populate any of these directories (they start empty).
- Phase 4 does **not** provide backup/snapshot of this tree (that is Phase 9).
