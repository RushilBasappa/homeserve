# Contract: Deletion Cascade (the six surfaces)

Defines exactly what a **single manual delete** must clear, and how each surface is verified.
This is the contract behind spec US2 / FR-006…FR-010a and SC-003. Mechanism: the operator adds
the title to Maintainerr's manual **"remove"** collection; Maintainerr enforces the cascade.

## The six surfaces

| # | Surface | Action | Verified by |
|---|---|---|---|
| 1 | **Disk** (`/srv/nfs/media`) | files deleted | path no longer exists |
| 2 | **qBittorrent** | torrent stopped + removed, download data deleted | title absent from qBit; no seed; `downloads/` data gone |
| 3 | **Radarr/Sonarr** | unmonitored **or** removed (so no re-download) | movie/series unmonitored/absent; no new grab on next search |
| 4 | **Jellyfin** | item removed | absent from Jellyfin library |
| 5 | **Plex** | item removed (on next scan — file is gone) | absent from Plex library after scan |
| 6 | **Seerr** | request cleared | title shows re-requestable, not "available" |

## Properties

- **Single action** (FR-006): one operator step (add to "remove" collection) triggers all six;
  the operator does not visit six apps.
- **No orphans** (SC-003): specifically no seeding torrent (surface 2), no ghost library entry
  (4/5), no still-monitored auto-re-download (3).
- **Manual-only** (FR-008): the cascade fires **only** from the operator's explicit add; no
  age/watch/disk rule exists to trigger it.
- **Granularity** (FR-006): whole movie; whole series **or** a single season for TV. Deleting a
  season leaves other seasons untouched.
- **Idempotent / re-runnable** (FR-009): if a surface was unreachable and missed, re-adding the
  title completes it; already-clean surfaces are no-ops.
- **Re-requestable** (FR-007e): after deletion, a fresh Seerr request treats the title as new and
  re-acquires cleanly.

## Timing note (dual-server)

Surface 5 (Plex) clears on Plex's **next library scan** after the file is gone, not
instantaneously. If instant Plex clearing is ever required, add a second Maintainerr instance
bound to Plex (R3 optional upgrade) — not part of v1.

## Verification (quickstart)

The delete drill in `quickstart.md` seeds one title present on **all six** surfaces (in library,
seeding, monitored, in both servers, available in Seerr), performs the single delete, and asserts
all six are cleared with zero orphans — this is SC-003.
