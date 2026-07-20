# Phase 0 — Research & Decisions: Media Stack

Each decision resolves a technical unknown from the spec. Format: **Decision → Rationale →
Alternatives rejected**. Findings verified against 2026 sources (cited inline).

---

## R1 — Media servers: Jellyfin + Plex, both on the Dell, QuickSync shared

**Decision**: Run **both** Jellyfin and Plex as separate stacks on the Dell, each with the
Intel iGPU passed through (`devices: ["/dev/dri:/dev/dri"]`) for QuickSync HW transcode. They
read the **same** `/srv/nfs/media` library (RO mounts) — one copy on disk. Jellyfin is the
**primary/reference** server (free, no account, always on); Plex adds the polished Fire-TV /
remote clients for Phase 7.

**Rationale**: Both are stateful (library + watch DB) → Dell (golden rule). The iGPU is only on
the hosts; the library and its watch-state must be co-located with the transcoder, so the Dell
is the only correct home. Both servers reading the same files means a file deletion in the arr
apps is reflected by both on scan (this is what makes single-instance deletion work — see R3).

**Alternatives rejected**: *Jellyfin only* — drops the Plex clients the operator wants. *Plex on
the Mac* — puts stateful Plex config on the Mac (violates the golden rule) and the Mac's Iris
6100 is the weaker iGPU. *Emby* — not requested. **Caveat carried to the plan**: Plex HW
transcode needs **Plex Pass**; Plex needs a **`PLEX_CLAIM`** token (from plex.tv/claim) on
first run. Both servers transcoding at once can exhaust the i3's iGPU + RAM — Plex is therefore
gated behind a measured-headroom check (Complexity Tracking).

---

## R2 — Download egress: Gluetun (Proton, WireGuard) + qBittorrent, native port-sync

**Decision**: `gluetun` with `VPN_SERVICE_PROVIDER=protonvpn`, `VPN_TYPE=wireguard`,
`VPN_PORT_FORWARDING=on`, `VPN_PORT_FORWARDING_PROVIDER=protonvpn`. qBittorrent runs with
`network_mode: "service:gluetun"` (all its traffic is inside the tunnel; killswitch is
Gluetun's default — if the tunnel is down, nothing egresses). Proton rotates the forwarded
port, so qBittorrent's listen port is kept in sync by Gluetun's **native**
`VPN_PORT_FORWARDING_UP_COMMAND`, which POSTs the new port to qBittorrent's Web API:

```
VPN_PORT_FORWARDING_UP_COMMAND=/bin/sh -c 'wget -qO- --post-data "json={\"listen_port\":{{PORTS}}}" http://127.0.0.1:8080/api/v2/app/setPreferences'
```

qBittorrent's Web UI is set to **bypass auth on localhost** so Gluetun reaches it without
credentials; the admin UI is still fronted by Traefik for humans.

**Rationale**: This is Proton's documented Gluetun path — port forwarding via NAT-PMP and a
**built-in** up-command, i.e. no cron/bash script file and no extra sidecar container. It
satisfies the operator's "no scripts" constraint while keeping healthy peer connectivity
(SC-002a). Reuses the existing `WIREGUARD_PRIVATE_KEY` / `WIREGUARD_ADDRESSES` mise secrets
(Proton issues standard WireGuard configs). Sources:
[gluetun-wiki VPN port forwarding](https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/vpn-port-forwarding.md),
[Proton+Gluetun guide](https://talhamangarah.com/blog/how-to-port-forward-with-proton-vpn-and-gluetun/).

**Alternatives rejected**: *cron script updating the port* — rejected (a bespoke script the
operator excluded). *`qbittorrent-natmap` sidecar* — works, but adds a container to do what
Gluetun's native up-command already does. *No port forwarding* — poor connectivity/seeding.

---

## R3 — Cascade delete: Maintainerr, ONE instance, manual collections

**Decision**: A **single Maintainerr** instance, connected to the **shared Radarr/Sonarr + the
download client + Seerr**, with **Jellyfin** as its reference media server. Deletion is driven
by **manual collections** (add the specific title → Maintainerr enforces the cascade): delete
files from disk, unmonitor/remove in Radarr/Sonarr, **remove the item from the download client**
(stops the seed), and clear the request in Seerr. Because the *file* is removed via the arr
apps, **Plex** reflects the removal on its next library scan — so one instance clears all six
surfaces (spec FR-007).

**Rationale**: Maintainerr is the only mature cleanup tool spanning Plex/Jellyfin/Emby and it
cascades to disk + arr + download client + Seerr
([Maintainerr README](https://github.com/jorenn92/Maintainerr)). It supports **manual**
collections and per-item add/exclude, which is exactly the operator's manual-only posture (no
age/watch/disk rules configured). Maintainerr does **not** support two media servers in one
instance ([docs](https://docs.maintainerr.info/configuration/)), but it doesn't need to here:
file deletion is the source-of-truth action and both servers read the same files.

**Alternatives rejected**: *Two Maintainerr instances (Plex + Jellyfin)* — only needed if the
operator wants Plex's library entry cleared **instantly** rather than on Plex's next scan, or
wants Plex-scoped rules later; recorded as an optional upgrade, not v1. *Janitorr/Reclaimerr* —
Jellyfin-centric and automation-first (conflicts with manual-only). *Custom delete script* —
excluded by the operator.

---

## R4 — Request app: Seerr (single instance, Jellyfin backend)

**Decision**: **Seerr** (the 2026 merge of Overseerr + Jellyseerr, `seerr-team/seerr`), **one
instance**, connected to **Jellyfin** as its media-server backend and to the shared
Radarr/Sonarr for fulfilment. It is the single request front door for the whole household
regardless of which player they use.

**Rationale**: Requests are **media-server-agnostic** — they flow to Radarr/Sonarr, which import
files both servers then see. "Availability" in Seerr = "is it in the library", and because both
servers read the same files, tracking availability from Jellyfin is identical to tracking it
from Plex. Jellyfin is chosen as the backend because it is account-free and always on. Seerr is
active and maintained (11.9k★, pushed 2026-07). Verified that **single-instance simultaneous
Plex+Jellyfin is NOT yet shipped** — issue
[#2576](https://github.com/seerr-team/seerr/issues/2576) requesting it is **closed as
duplicate** — so one backend per instance is the correct assumption.

**Alternatives rejected**: *Two Seerr instances (one per server)* — two request URLs, splits the
household; unnecessary since acquisition is server-agnostic. *Wait for simultaneous support* —
not shipped; don't block on it.

---

## R5 — Inter-app wiring: three planes, native-first, deterministic keys

**Decision**: Establish all connections from code, no clicks, no scripts:
1. **Deterministic API keys** — set each servarr app's key via env from mise:
   `RADARR__AUTH__APIKEY=${RADARR_API_KEY}` (same for Sonarr/Prowlarr), so every key is known at
   deploy time ([Radarr env vars, Servarr wiki](https://wiki.servarr.com/radarr/environment-variables)).
2. **Prowlarr native app-sync** — the plane-3 step adds Radarr+Sonarr as *Applications* in
   Prowlarr once; Prowlarr then auto-propagates all indexers and keeps them synced (first-party,
   maintained).
3. **Configarr** — a containerised, YAML-driven TRaSH sync applies quality profiles/custom
   formats to Radarr/Sonarr, idempotently.
4. **Plane-3 wiring** — an idempotent Ansible `uri` play at `stacks/arr/configure/wire.yml`
   (run post-deploy) sets the connections no native tool covers: qBittorrent as the download
   client in Radarr/Sonarr; Radarr/Sonarr as apps in Prowlarr; Seerr→Radarr/Sonarr; Bazarr→
   Radarr/Sonarr. It GETs current state and POSTs only what's missing (idempotent; re-run = no-op).

Jellyfin/Plex/Seerr API keys that are **not** env-settable are created once and read back by the
same play (e.g. create a Jellyfin API key via its API, feed it to Maintainerr; Seerr connects to
Jellyfin via admin login). This is the residual the play owns.

**Rationale**: Maximises maintained/native mechanisms; the deterministic keys are the linchpin
that makes declarative wiring possible (FR-024). Honours the three-plane separation (FR-023a):
`provision/` stays machine-only; wiring is co-located and post-deploy.

**Alternatives rejected**: *Buildarr* — the one full-declarative tool, **barred** as unmaintained
(last release 2023, commit mid-2024). *Manual UI wiring* — not reproducible. *Random first-boot
keys* — breaks pre-wiring.

**Accepted tradeoff**: the `uri` bodies are app-version-sensitive; a major arr upgrade may need a
payload update — surfaced as a **visible play failure**, never silent drift (spec edge case).

---

## R6 — Self-maintenance helpers: Cleanuparr, Huntarr, Byparr, Configarr, Unpackerr

**Decision**: Add **Cleanuparr** (removes stalled/blocked/malware downloads, blocklists, re-searches),
**Huntarr** (hunts missing items + upgrades on a schedule), **Byparr** (FlareSolverr successor
for bot-protected indexers, added to Prowlarr), **Configarr** (quality, R5), **Unpackerr**
(extracts archived releases for the arr apps).

**Rationale**: These are the "modern 2026" additions the operator selected; each fixes a distinct
stock-arr failure mode (wedged queues, permanently-missing items, dead Cloudflare indexers,
junk quality, un-extracted archives). All maintained. Cleanuparr is the current unified queue
janitor ([Cleanuparr](https://github.com/Cleanuparr/Cleanuparr)).

**Alternatives rejected**: *Decluttarr* — narrower than Cleanuparr. *FlareSolverr* — effectively
superseded by Byparr. *arr-scripts* — bespoke scripts, excluded.

---

## R7 — Node placement & RAM budget

**Decision**: **Dell** (stateful, GPU, egress): `arr` stack (gluetun+qbit+prowlarr+radarr+sonarr+
bazarr+unpackerr+configarr), `jellyfin`, `plex`, `seerr`, `maintainerr`, `jellystat`. **Mac**
(stateless only): `media-helpers` (byparr, cleanuparr, huntarr). Helpers on the Mac reach the
arr apps on the Dell over the LAN (`10.0.0.70`).

**Rationale**: Golden rule — anything holding config/library/watch state is on the Dell;
Byparr/Cleanuparr/Huntarr are effectively stateless workers, so they offload to the Mac to
relieve the Dell's 7.5 GB. The Dell already runs the edge + Komodo Core, so headroom is the
binding constraint → **phase the rollout** (P1: `arr`+`jellyfin`+`seerr`+`maintainerr`; P2:
`plex`+`jellystat`+helpers) and **measure** before Plex lands.

**Alternatives rejected**: *Everything on the Dell* — likely OOM under transcode. *Stateful apps
on the Mac* — violates the golden rule and the one-backup-source design.

---

## R8 — One `arr` stack vs many

**Decision**: The acquisition pipeline is **one** Compose stack (`stacks/arr/`) — gluetun,
qbittorrent (netns=gluetun), prowlarr, radarr, sonarr, bazarr, unpackerr, configarr.

**Rationale**: qBittorrent must share Gluetun's network namespace, and the arr apps are
lifecycle-coupled to the download client. One unit makes intra-pipeline DNS trivial (Radarr
reaches qBit at `gluetun:8080`) and lets the plane-3 wiring live co-located. Single-purpose apps
stay separate stacks per convention.

**Alternatives rejected**: *One stack per arr app* — many Komodo entries, cross-stack networking
for the shared VPN netns, wiring scattered. *Everything (servers too) in one mega-stack* — poor
separation; servers have different lifecycle/placement/GPU needs.

---

## R9 — Networking, TLS, mounts

**Decision**: HTTP UIs join the external `traefik` network and get standard wildcard-TLS labels
(`<app>.ragnaforge.xyz`, CONVENTIONS "Traefik routing labels") — no host ports. qBittorrent's UI
is reached via Gluetun (which is on the `traefik` network; qBit shares its netns), routed as
`qbittorrent.ragnaforge.xyz`. Library/download mounts follow the Phase-4 contract: `arr` mounts
the whole tree RW; servers mount `media/` RO. All media containers run `PUID=1000`/`PGID=1000`,
`TZ` from a Komodo variable.

**Rationale**: Consistent with Phases 3–4; no new public surface (torrent traffic egresses via
Proton, not an inbound port). Hardlinks preserved by keeping qBit's downloads and servarr roots
in the one Phase-4 filesystem.

**Alternatives rejected**: *Publishing app host ports* — violates the "no host ports for HTTP"
rule. *Separate media network only* — UIs still need Traefik for TLS.

---

## R10 — Secrets (new mise placeholders)

**Decision**: Add to `.mise.toml.example`: `RADARR_API_KEY`, `SONARR_API_KEY`,
`PROWLARR_API_KEY`, `BAZARR_API_KEY` (deterministic 32-hex, `openssl rand -hex 16`); `PLEX_CLAIM`
(short-lived, from plex.tv/claim, first-run only); `QBIT_WEBUI_PASSWORD` if not using
localhost-bypass for humans. Reuse existing `WIREGUARD_PRIVATE_KEY`/`WIREGUARD_ADDRESSES` for
Gluetun→Proton. Seerr/Maintainerr use API keys minted at wiring time, not stored secrets.

**Rationale**: Deterministic keys (R5) must be real secrets (they grant API access) → mise, never
git. `PLEX_CLAIM` is the only Plex bootstrap secret. Matches the existing secret-flow
(`provision/sync-secrets.yml` pushes `.mise.toml` to nodes; Komodo injects `${VAR}`).

**Alternatives rejected**: *Let apps self-generate keys* — non-deterministic, breaks pre-wiring.
*Store Plex token long-term* — `PLEX_CLAIM` is single-use; the server keeps its own token after.

---

## R11 — Deploy & wiring orchestration order

**Decision**: Bring-up order (runbook `phase5-media.md`): (1) `make sync-secrets` (new keys to
nodes); (2) deploy `arr` via Komodo; (3) run `stacks/arr/configure/wire.yml` **after** the arr
apps report healthy; (4) deploy `jellyfin`, `seerr`, `maintainerr`; wire Seerr→arr/Jellyfin and
Maintainerr→arr/Jellyfin/Seerr/qBit; (5) **P2**: measure Dell RAM, then deploy `plex`,
`jellystat`, and the Mac `media-helpers`; add Byparr to Prowlarr, connect helpers to the arr
apps.

**Rationale**: The plane-3 wiring must run post-deploy against healthy apps with keys already
pinned (FR-023a, spec edge case "wiring step ordering"). Phasing enforces the RAM gate.

**Alternatives rejected**: *Wire during provisioning* — apps aren't up yet; conflates planes.
*Deploy everything then wire once* — fine functionally, but phasing manages RAM and lets P1
deliver the MVP (request→play→delete) before the heavier P2 pieces.
