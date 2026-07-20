# Quickstart — Validate the Media Stack (SC-001…SC-011)

Behavioural validation that the phase works end-to-end. Run after deploy + wiring. Each scenario
maps to a Success Criterion in `spec.md`. Full bring-up steps live in
`docs/runbooks/phase5-media.md`; this is the **proof** guide.

## Prerequisites

- Phases 1–4 green (Docker, Komodo, Traefik + wildcard TLS, AdGuard, `/srv/nfs` verified).
- `.mise.toml` filled with the new keys (`stack-inventory.md` → New secrets); `make sync-secrets` run.
- **P1 deployed**: `arr`, `jellyfin`, `seerr`, `maintainerr`; `stacks/arr/configure/wire.yml` run.
- **P2 deployed** (for SC-007/008 + stats): `plex`, `jellystat`, `media-helpers`.
- A Proton VPN plan with port forwarding; a working torrent indexer in Prowlarr.

## Scenario 1 — Request → play (SC-001)  [US1]

1. In `https://seerr.ragnaforge.xyz`, request one movie known to exist on the indexer.
2. Observe: Radarr grabs → qBittorrent downloads → import to `/srv/nfs/media/movies`.
3. Open `https://jellyfin.ragnaforge.xyz`, play it.
- **Pass**: playable with **zero** manual file/app handling between request and play.

## Scenario 2 — VPN killswitch / no leak (SC-002)  [US1, critical]

1. Note qBittorrent's egress IP (qBit → Tools, or a tracker announce) — must be the **Proton**
   exit IP, never `76.102.108.83`.
2. Force the tunnel down: stop the `gluetun` service (leave `qbittorrent` running).
3. Observe qBittorrent: **no** outbound connectivity (transfers stall), and **no** traffic exits
   over the home line.
4. Restart `gluetun`: downloads resume automatically.
- **Pass**: 0% home-IP egress; tunnel-down fully blocks torrent traffic; auto-resume on reconnect.

## Scenario 3 — Port forwarding & sync (SC-002a)  [US1]

1. In qBittorrent, confirm the listen port equals Proton's current forwarded port and the client
   reports **connectable** (green).
2. Restart `gluetun` (forces a new forwarded port).
3. Within one update cycle, qBittorrent's listen port re-syncs to the new port automatically.
- **Pass**: connectable/open port; auto re-sync after restart with no operator action.

## Scenario 4 — Single cascade delete, six surfaces (SC-003)  [US2, headline]

1. Pick a title that is: in `/srv/nfs/media`, **seeding** in qBittorrent, **monitored** in
   Radarr/Sonarr, visible in **Jellyfin** and **Plex**, **available** in Seerr.
2. Add it to Maintainerr's manual **"remove"** collection; let Maintainerr enforce.
3. Verify per `contracts/deletion-cascade.md`:
   - disk path gone · torrent removed + no seed + `downloads/` data gone · unmonitored/removed in
     arr · absent from Jellyfin · absent from Plex (after scan) · re-requestable in Seerr.
- **Pass**: all six cleared, **zero** orphans. **Re-run** the add on the now-deleted title → no
  error, no change (idempotent, SC-005).

## Scenario 5 — No automatic deletion (SC-004)  [US2]

1. Confirm Maintainerr has **no** age/watch/disk rules — only the manual "remove" collection.
2. Over an observation window (e.g. leave a watched, old title in place), confirm **nothing** is
   deleted without an explicit add.
- **Pass**: 0 media removed without operator action.

## Scenario 6 — Hardlink, not copy (SC-006)  [US1]

1. After an import, compare inode/link-count of the library file vs the `downloads/complete` file.
- **Pass**: same inode (hardlink); no library-sized extra disk used; seeding continues.

## Scenario 7 — Self-maintenance: stuck download auto-cleared (SC-007)  [US3, P2]

1. Introduce a stalled/blocked download (or wait for one).
2. Cleanuparr removes it, blocklists the release, triggers a fresh search — no operator action.
- **Pass**: removed + blocklisted + re-searched within one cleanup cycle.

## Scenario 8 — Dual-server, one library (SC-008)  [US4, P2]

1. Play the **same** title from Jellyfin and from Plex.
2. Confirm one copy on disk (Scenario 6 already asserts no duplication).
- **Pass**: playable from both against the same file; single on-disk copy.

## Scenario 9 — Quality from code (SC-009)  [US3]

1. Inspect Radarr/Sonarr quality profiles → match `stacks/arr/configarr/config.yml` (TRaSH).
2. Re-run Configarr → no changes.
- **Pass**: profiles match after deploy; second run idempotent.

## Scenario 10 — Reachability (SC-010)

1. Each UI (`qbittorrent`, `prowlarr`, `radarr`, `sonarr`, `bazarr`, `jellyfin`, `plex`, `seerr`,
   `maintainerr`, `jellystat`, `byparr`, `cleanuparr`, `huntarr`).ragnaforge.xyz loads with valid TLS.
2. Each appears on the Homepage dashboard.
- **Pass**: 100% reachable with valid cert + on Homepage.

## Scenario 11 — Reproducible wiring, no clicks (SC-011)

1. On a clean rebuild: deploy stacks, run `stacks/arr/configure/wire.yml`.
2. Confirm indexers propagated (Prowlarr → Radarr/Sonarr), download client present, Seerr/Bazarr
   linked — with **zero** manual UI clicks and no scripts.
3. Re-run the play → no changes.
- **Pass**: all inter-app connections present from code; idempotent re-run; Buildarr not used.

---

### Result log (fill during validation)

| SC | Scenario | Result | Evidence / notes |
|---|---|---|---|
| SC-001 | request→play | | |
| SC-002 | killswitch/no-leak | | |
| SC-002a | port sync | | |
| SC-003 | 6-surface delete | | |
| SC-004 | no auto-delete | | |
| SC-005 | delete idempotent | | |
| SC-006 | hardlink | | |
| SC-007 | queue cleanup | | |
| SC-008 | dual-server | | |
| SC-009 | quality from code | | |
| SC-010 | reachability | | |
| SC-011 | wiring reproducible | | |
