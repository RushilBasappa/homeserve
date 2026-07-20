# Contract: Stack Inventory (stacks × node × ports × mounts × secrets)

The interface this phase adds to the fleet. Komodo declares each stack in `komodo/stacks.toml`;
every HTTP app is reached at `https://<name>.ragnaforge.xyz` via Traefik (no host ports unless
noted). All media containers run `PUID=1000`/`PGID=1000` (Phase-4 contract).

## Stacks

| Stack (dir) | Node | Services | Subdomain(s) | Config volume(s) | Media mount |
|---|---|---|---|---|---|
| `arr` | Dell | gluetun, qbittorrent, prowlarr, radarr, sonarr, bazarr, unpackerr, configarr | `qbittorrent`, `prowlarr`, `radarr`, `sonarr`, `bazarr` | `qbittorrent-config`, `prowlarr-config`, `radarr-config`, `sonarr-config`, `bazarr-config` | whole `/srv/nfs` tree **RW** |
| `jellyfin` | Dell | jellyfin | `jellyfin` | `jellyfin-config` | `/srv/nfs/media` **RO** |
| `plex` | Dell | plex | `plex` | `plex-config` | `/srv/nfs/media` **RO** |
| `seerr` | Dell | seerr | `seerr` | `seerr-config` | — |
| `maintainerr` | Dell | maintainerr | `maintainerr` | `maintainerr-config` | — (acts via APIs) |
| `jellystat` | Dell | jellystat, jellystat-db (Postgres) | `jellystat` | `jellystat-db` | — |
| `media-helpers` | **Mac** | byparr, cleanuparr, huntarr | `byparr`, `cleanuparr`, `huntarr` | `cleanuparr-config`, `huntarr-config` (Dell? see note) | — |

**Note on Mac helpers & the golden rule**: Byparr is stateless (no volume). Cleanuparr/Huntarr
keep small config; if that config is state it must live on the **Dell** per the golden rule.
Resolution (tasks phase): run them **stateless** (config via env / mounted read-only from git)
so the Mac holds no persistent state — otherwise relocate them to the Dell. This must be settled
before they land (P2).

## Ports (host-published — the exception, not the rule)

| Port | Proto | Stack | Exposure | Why |
|---|---|---|---|---|
| (none new for HTTP) | — | all UIs | via Traefik only | "no host ports for HTTP" rule holds |
| 6881 | TCP/UDP | arr (via gluetun) | **outbound only via Proton**; inbound = Proton forwarded port | torrent peer port — **not** router-forwarded; no home-IP exposure |

qBittorrent listens on the **Proton-forwarded** port (rotating, synced by Gluetun's
`VPN_PORT_FORWARDING_UP_COMMAND`). No inbound router forward is added — this is not a public
service.

## New secrets (`.mise.toml.example` placeholders — real values only in gitignored `.mise.toml`)

| Var | Used by | Notes |
|---|---|---|
| `RADARR_API_KEY` | radarr (`RADARR__AUTH__APIKEY`), wire.yml, seerr, maintainerr, cleanuparr, huntarr | 32-hex, `openssl rand -hex 16` — deterministic |
| `SONARR_API_KEY` | sonarr, wire.yml, … | as above |
| `PROWLARR_API_KEY` | prowlarr, wire.yml | as above |
| `BAZARR_API_KEY` | bazarr, wire.yml | as above |
| `PLEX_CLAIM` | plex (first run) | short-lived token from plex.tv/claim |
| `QBIT_WEBUI_PASSWORD` | qbittorrent (human login; Gluetun uses localhost-bypass) | optional if UI is Traefik-only + localhost-bypass |
| *(reused)* `WIREGUARD_PRIVATE_KEY`, `WIREGUARD_ADDRESSES` | gluetun → Proton | already in `.mise.toml.example` |

## Guarantees

1. **Egress isolation**: only qBittorrent traffic transits Proton; tunnel-down = no egress
   (killswitch). No torrent traffic reveals the home IP.
2. **Hardlink preservation**: qBittorrent save paths and servarr root folders stay within the one
   Phase-4 filesystem → imports are hardlinks, not copies.
3. **Stateful → Dell**: every config volume above is a **local named volume on the Dell**; no app
   config on `/srv/nfs`; the Mac holds no persistent state.
4. **Deterministic wiring**: every servarr API key is fixed from mise at deploy time; the plane-3
   play reproduces all connections on a clean rebuild.

## Consumer obligations (later phases)

- **Phase 7 (VPN #2)**: family/friends reach `jellyfin`/`plex`/`seerr` over wg-easy; optional
  nftables fence to media only. No change to this contract.
- **Phase 8 (monitoring)**: scrape container health / disk; alert on qBit "not connectable"
  (stale port) and disk pressure.
- **Phase 9 (backups)**: back up the `*-config` volumes and `jellystat-db`; media is
  re-acquirable and out of backup scope by default.
