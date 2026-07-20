# Phase 1 — Data Model: Media Stack

This phase has no application database of its own; the "entities" are the domain objects the
stack manages and the relationships the wiring establishes. Modelling them makes the deletion
cascade and the wiring contract precise.

---

## Entities

### Media item
The unit a household member requests, watches, and the operator deletes.
- **Attributes**: title, type (movie | series | season | episode), library path under
  `/srv/nfs/media/{movies,tv}`, monitored-state (in Radarr/Sonarr), availability-state (in Seerr).
- **Represented in**: files on disk · Radarr/Sonarr (the file authority) · Jellyfin library ·
  Plex library · Seerr (as available) · Maintainerr (as a collection member when marked for deletion).
- **Lifecycle**: `requested → searching → downloading → imported (available) → [watched] → deleted`.
- **Deletion scope**: whole movie; whole series **or** a single season for TV (spec FR-006).

### Request
A member's ask, the entry point of the pipeline.
- **Attributes**: requester, media item, status (pending | approved | available | removed).
- **Owned by**: Seerr. **Drives**: Radarr/Sonarr acquisition. **Cleared by**: the cascade delete
  (so the title can be requested fresh — FR-007e).

### Download
An in-progress or seeding torrent.
- **Attributes**: linked media item, state (downloading | seeding | stalled | blocked),
  save path under `/srv/nfs/downloads/{incomplete,complete}`, forwarded listen port.
- **Owned by**: qBittorrent (inside Gluetun's netns). **Constraints**: egresses **only** via
  Proton; listen port tracks Proton's rotating forwarded port. **Cleaned up by**: the cascade
  delete (stop + remove + delete data) and by Cleanuparr (stalled/blocked/malware).

### Quality profile / custom format set
The code-defined rules for acceptable releases and upgrades.
- **Attributes**: profile name, cutoff, custom-format scores (from TRaSH).
- **Owned by**: Radarr/Sonarr. **Source of truth**: `stacks/arr/configarr/config.yml` applied by
  Configarr (idempotent). **Never** hand-entered.

### Indexer
A configured release source.
- **Attributes**: name, protocol (torrent), URL, may sit behind bot-protection.
- **Managed centrally in**: Prowlarr. **Propagated by**: Prowlarr native app-sync → Radarr/Sonarr.
  **Bot-protected ones** resolved via Byparr.

### Library
The shared on-disk media tree — the single source of truth deletion mutates.
- **Path**: `/srv/nfs/media/{movies,tv}` (Phase-4 contract). **Read by**: Jellyfin + Plex (RO).
  **Written by**: Radarr/Sonarr import (RW, hardlink from `downloads/`).

### Deletion collection
Maintainerr's mechanism for the manual cascade.
- **Attributes**: collection name (e.g. "remove"), members (media items the operator added),
  enforced actions (delete files · unmonitor/remove in arr · remove from download client ·
  remove from media server · clear Seerr request).
- **Owned by**: Maintainerr. **Trigger**: operator adds a title (manual); **no** age/watch/disk
  rules configured (spec FR-008).

### App connection (wiring edge)
A directed integration between two apps, established in plane 3.
- **Attributes**: source app, target app, credential (API key / admin login), purpose.
- **The edges** (see `contracts/wiring.md`): qBit→Radarr, qBit→Sonarr, Radarr→Prowlarr,
  Sonarr→Prowlarr, Byparr→Prowlarr, Seerr→Radarr, Seerr→Sonarr, Seerr→Jellyfin,
  Maintainerr→{Radarr,Sonarr,Jellyfin,Seerr,qBit}, Cleanuparr→{Radarr,Sonarr,qBit}, Huntarr→{Radarr,Sonarr}.

---

## Relationships (the pipeline graph)

```text
member → Seerr ──request──▶ Radarr / Sonarr ──search──▶ Prowlarr ──▶ indexers (via Byparr)
                                   │                         ▲
                                   │ grab                    │ app-sync (native)
                                   ▼                         │
                         qBittorrent (in Gluetun ── Proton egress + fwd port)
                                   │ complete
                                   ▼
                    /srv/nfs/downloads ──hardlink import──▶ /srv/nfs/media
                                                                │
                                              ┌─────────────────┼─────────────────┐
                                           Jellyfin           Plex             Seerr (available)
                                              │                 │
                                        member plays      member plays
```

## Deletion cascade (the mutation)

```text
operator ──adds title──▶ Maintainerr "remove" collection ──enforces──▶
    ├─ Radarr/Sonarr: delete files (disk)  +  unmonitor/remove
    ├─ qBittorrent:   stop + remove torrent + delete download data
    ├─ Jellyfin:      item removed
    ├─ Plex:          item removed on next scan (file gone)
    └─ Seerr:         request cleared  → title re-requestable
```

Idempotent: re-adding an already-deleted title is a no-op on already-clean surfaces (FR-009).

## Three configuration planes (organizing model — spec FR-023a)

| Plane | Operates on | Where | When |
|---|---|---|---|
| Machine | OS (Docker, NFS, sysctl) | `provision/` (Ansible, SSH) | pre-Docker, per host — **untouched by this phase** |
| Deployment | Compose stacks | `komodo/stacks.toml` + `stacks/*/compose.yaml` | on deploy (Komodo) |
| Application | app HTTP APIs (the wiring edges above) | `stacks/arr/configure/wire.yml` + Configarr | **post-deploy**, idempotent |
