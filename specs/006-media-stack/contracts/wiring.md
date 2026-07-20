# Contract: Plane-3 Application Wiring

The connections `stacks/arr/configure/wire.yml` (+ Configarr + Prowlarr native sync) must
establish **post-deploy**, **idempotently**, with **no manual UI clicks and no bespoke scripts**
(spec FR-023/FR-023a). Each edge is GET-then-POST: read current state, add only if missing,
re-run = no-op.

## Preconditions

- All target apps deployed and healthy.
- servarr API keys already pinned via env from mise (`RADARR__AUTH__APIKEY=${RADARR_API_KEY}`, etc.).
- Jellyfin admin exists (first-run); Plex claimed (P2).

## Edges

| # | Source | → Target | Credential | Purpose | Mechanism |
|---|---|---|---|---|---|
| 1 | Radarr | qBittorrent | qBit login / localhost | download client | `uri` POST `/api/v3/downloadclient` |
| 2 | Sonarr | qBittorrent | qBit login / localhost | download client | `uri` POST `/api/v3/downloadclient` |
| 3 | Prowlarr | Radarr | `RADARR_API_KEY` | register app → auto-sync indexers | `uri` POST `/api/v1/applications` |
| 4 | Prowlarr | Sonarr | `SONARR_API_KEY` | register app → auto-sync indexers | `uri` POST `/api/v1/applications` |
| 5 | Prowlarr | Byparr | Byparr URL | bot-protection proxy (indexer) | `uri` POST `/api/v1/indexerProxy` (P2) |
| 6 | Radarr/Sonarr | (indexers) | — | **auto-populated** by Prowlarr sync | native (no play step) |
| 7 | Configarr | Radarr/Sonarr | `*_API_KEY` | TRaSH quality profiles/custom formats | Configarr container reads `config.yml` |
| 8 | Seerr | Radarr | `RADARR_API_KEY` | fulfilment target | `uri`/settings against Seerr API |
| 9 | Seerr | Sonarr | `SONARR_API_KEY` | fulfilment target | `uri`/settings against Seerr API |
| 10 | Seerr | Jellyfin | Jellyfin admin login | media-server backend (availability) | Seerr setup API |
| 11 | Bazarr | Radarr | `RADARR_API_KEY` | subtitle source | `uri` POST bazarr API |
| 12 | Bazarr | Sonarr | `SONARR_API_KEY` | subtitle source | `uri` POST bazarr API |
| 13 | Maintainerr | Radarr/Sonarr | `*_API_KEY` | delete files + unmonitor | Maintainerr settings API |
| 14 | Maintainerr | Jellyfin | Jellyfin API key* | reference media server | Maintainerr settings API |
| 15 | Maintainerr | Seerr | Seerr API key* | clear request on delete | Maintainerr settings API |
| 16 | Maintainerr | qBittorrent | qBit login | remove seeding torrent | Maintainerr settings API |
| 17 | Cleanuparr | Radarr/Sonarr/qBit | `*_API_KEY` / qBit | queue cleanup | Cleanuparr config (P2) |
| 18 | Huntarr | Radarr/Sonarr | `*_API_KEY` | hunt missing/upgrades | Huntarr config (P2) |

`*` = keys **not** env-settable (Jellyfin, Seerr) are **minted once via the app's API** by the
play and passed to the consumer — the residual the play owns (spec R5).

## Idempotency & failure

- **Idempotent**: every edge GETs existing config and skips if present; a second run changes
  nothing (SC-011).
- **Visible failure**: an app API rejecting a hand-encoded body (e.g. schema drift after a major
  upgrade) **fails the play loudly** — never a silent unwired stack (spec edge case).
- **Ordering**: runs only after apps are healthy with keys pinned (spec edge case "wiring step
  ordering").

## What is NOT wired here

- Indexers into Radarr/Sonarr (edge 6) — Prowlarr does this natively after edges 3–4.
- Quality profiles (edge 7) — Configarr owns these, not the `uri` play.
- Any age/watch/disk **deletion rules** in Maintainerr — **intentionally absent** (manual-only,
  FR-008); only the manual "remove" collection exists.
