# Runbook — Phase 5: Media Stack (ARR + Jellyfin/Plex)

Stand up the self-service media pipeline on top of the Phase-4 `/srv/nfs` tree and
the Phase-3 edge: a household member requests a title in **Seerr**, it is acquired
over **Proton VPN** (qBittorrent behind **Gluetun**, killswitch + NAT-PMP port
forwarding), imported by **Radarr/Sonarr** as a hardlink into `/srv/nfs/media`, and
played from **both Jellyfin and Plex**. On top ride a **single manual cascade
delete** (Maintainerr), a **self-maintaining** layer (Prowlarr app-sync, Configarr,
Cleanuparr, Huntarr, Byparr), and **reproducible-from-code wiring**.

> **One-line flow:** `make sync-secrets` (new keys) → deploy `arr` → run
> `stacks/arr/configure/wire.yml` (post-deploy, idempotent) → deploy `jellyfin` +
> `seerr` + `maintainerr` (P1, the MVP) → **measure Dell RAM** → deploy `plex` +
> `jellystat` + Mac `media-helpers` (P2) → prove SC-001..011 in `quickstart.md`.

## Prerequisites

- Phases 1–4 green: Docker, Komodo (Core on the Dell), Traefik + wildcard TLS,
  AdGuard, and the `/srv/nfs` tree verified (`docs/runbooks/phase4-storage.md`).
- `ssh ragnaforge-dell` (10.0.0.70) and `ssh ragnaforge-mac` (10.0.0.71) work.
- A Proton VPN plan **with port forwarding**; reuse the existing
  `WIREGUARD_PRIVATE_KEY` / `WIREGUARD_ADDRESSES` (Proton issues standard WireGuard
  configs). At least one working torrent indexer to add to Prowlarr.
- The new keys filled in the gitignored `.mise.toml` (see below) and pushed with
  `make sync-secrets`.

---

## Bring-up order

Follow the spec's story priorities so the RAM budget stays honest (research R7/R11).

1. **Setup** — fill `.mise.toml` (new keys), `make sync-secrets`.
2. **Foundational (`arr`)** — deploy via Komodo; wait for every container healthy and
   Gluetun's tunnel up; run `stacks/arr/configure/wire.yml`; add an indexer in
   Prowlarr; confirm native app-sync propagated it to Radarr/Sonarr.
3. **US1 (MVP)** — deploy `jellyfin` (first-run admin + libraries) and `seerr`
   (backend = Jellyfin; fulfilment = Radarr/Sonarr). Prove request→play.
4. **US2** — deploy `maintainerr`; create the manual **"remove"** collection; prove
   the six-surface delete.
5. **US3** — enable Configarr; deploy the Mac `media-helpers`; wire Byparr into
   Prowlarr and Cleanuparr/Huntarr to the arr apps.
6. **US4 (RAM-gated)** — run the **RAM headroom gate** below; if it passes, deploy
   `plex` (claim it) and `jellystat`.
7. **Polish** — reachability, reproducible-wiring proof, secret/state sanity.

Per-stack, always: `compose.yaml` → declare in `komodo/stacks.toml` → deploy via
Komodo → **wire post-deploy** (plane 3) → verify. Never wire before an app is
healthy with its API key pinned.

---

## New secrets (`.mise.toml`)

Fill these in the gitignored `.mise.toml` (placeholders in `.mise.toml.example`),
then `make sync-secrets` to push to both nodes:

| Var | How to generate | Used by |
|---|---|---|
| `RADARR_API_KEY` | `openssl rand -hex 16` | radarr, wire.yml, seerr, maintainerr, cleanuparr, huntarr |
| `SONARR_API_KEY` | `openssl rand -hex 16` | sonarr, wire.yml, … |
| `PROWLARR_API_KEY` | `openssl rand -hex 16` | prowlarr, wire.yml |
| `BAZARR_API_KEY` | `openssl rand -hex 16` | bazarr, wire.yml |
| `QBIT_WEBUI_PASSWORD` | a strong password | qBittorrent human login |
| `PLEX_CLAIM` | plex.tv/claim (short-lived, **P2 first-run only**) | plex |
| *(reused)* `WIREGUARD_PRIVATE_KEY`, `WIREGUARD_ADDRESSES` | Proton WireGuard config | gluetun → Proton |

The four servarr keys are **deterministic** — fixed at deploy time so plane-3 wiring
is fully declarative. Jellyfin/Seerr API keys are **not** stored secrets; they are
minted once by the wiring step and handed to the consumer (Maintainerr, Jellystat).

---

## Proton egress + killswitch (leak test)

`arr` routes only qBittorrent's traffic through Proton (`network_mode:
service:gluetun`). Gluetun's default killswitch means **tunnel-down = no egress**.

- **Exit IP check**: qBittorrent's observed egress IP must be the **Proton** exit IP,
  never the home IP (`76.102.108.83`).
- **Leak test (SC-002)**: stop the `gluetun` service, leave `qbittorrent` running;
  confirm zero home-line egress and stalled transfers; restart `gluetun` → auto-resume.

_Evidence: see Verification evidence → SC-002._

## Port-forward sync

Proton rotates the forwarded port; Gluetun's **native**
`VPN_PORT_FORWARDING_UP_COMMAND` POSTs the new port to qBittorrent's Web API (no cron,
no sidecar). For that POST to succeed without credentials, qBittorrent must
**bypass auth on localhost** — set on first run (see below).

- **Check (SC-002a)**: qBittorrent reports **connectable** on Proton's current port;
  restart `gluetun` → the listen port re-syncs automatically within one cycle.

## qBittorrent first-run (one-time, in the volume)

LinuxServer qBittorrent seeds its config in `qbittorrent-config` on first run:

1. Read the temporary admin password from the container log
   (`docker logs qbittorrent | grep -i password`), log in at
   `https://qbittorrent.ragnaforge.xyz`, and set the password to
   `${QBIT_WEBUI_PASSWORD}`.
2. **Options → Web UI →** enable **"Bypass authentication for clients on localhost"**
   (so Gluetun's port-sync POST to `127.0.0.1:8080` works), and set the alternate Web
   UI / trusted settings as needed. Save.
3. Set the default save path to `/data/downloads/complete` and the incomplete path to
   `/data/downloads/incomplete` (the `arr` bind maps `/srv/nfs` → `/data`).

These are the only qBittorrent settings not expressible from code (they live in the
config volume, which is Dell-local and backed up).

---

## Delete drill (six surfaces)

Per `specs/006-media-stack/contracts/deletion-cascade.md`. Seed one title present on
**all six** surfaces (on disk, seeding in qBittorrent, monitored in Radarr/Sonarr,
visible in Jellyfin **and** Plex, available in Seerr), add it to Maintainerr's manual
**"remove"** collection, and verify all six clear with **zero** orphans:

1. **Disk** — path under `/srv/nfs/media` gone.
2. **qBittorrent** — torrent removed, no seed, `downloads/` data gone.
3. **Radarr/Sonarr** — unmonitored/removed (no re-grab on next search).
4. **Jellyfin** — item absent.
5. **Plex** — item absent after its next scan.
6. **Seerr** — request cleared (title re-requestable).

Re-adding the now-deleted title = no error, no change (idempotent, SC-005). Confirm
**no** age/watch/disk rules exist in Maintainerr (manual-only, SC-004).

---

## Wiring re-run (idempotent)

`stacks/arr/configure/wire.yml` (Ansible `uri`) establishes the plane-3 edges no
native tool covers (qBit→Radarr/Sonarr download client, Radarr/Sonarr→Prowlarr apps,
Bazarr→Radarr/Sonarr, Seerr→arr/Jellyfin), GET-then-POST so a re-run is a **no-op**.
Prowlarr's own app-sync then propagates indexers; Configarr owns quality profiles.

Run it **after** the arr apps are healthy with keys pinned:

```sh
cd stacks/arr/configure && mise exec -- ansible-playbook wire.yml
```

- **First run**: adds the missing edges (`changed`).
- **Second run**: reports **no changes** (SC-011 precondition).
- **Schema drift** after a major arr upgrade: the play **fails loudly** — never a
  silent unwired stack.

_Buildarr is **not** used (unmaintained, barred). No bespoke long-lived scripts._

---

## RAM headroom gate (before Plex — T034)

Plex is **gated** on measured headroom (plan Complexity Tracking). With P1 running
(`arr` + `jellyfin` + `seerr` + `maintainerr`), drive a **Jellyfin HW transcode**
plus an **active download**, then measure the Dell:

```sh
ssh ragnaforge-dell 'free -h; docker stats --no-stream'
```

- **GO** — comfortable free RAM under load (rule of thumb: ≥1 GB free with the
  transcode + download running): deploy `plex` + `jellystat`.
- **DEFER** — if it's tight/OOM-risky: **defer Plex to Phase 12** (Mac Mini, 32 GB)
  per the escape hatch; keep Jellyfin as the single server for now. Record the
  decision below either way.

**Decision (2026-07-20): GO.** Measured with edge + Komodo + arr + Jellyfin + Seerr
running (idle, no active transcode): **4.9 GiB available** of 7.5 GiB (used 2.6 GiB;
buff/cache 5.1 GiB reclaimable; swap unused). Plex idles ~200 MiB, ~0.5–1 GiB under
transcode → comfortable headroom. Caveat: this is an idle reading; the binding limit
for *concurrent* Plex+Jellyfin transcode is the i3-10110U iGPU, not RAM. Operator set
Plex as the **primary** server (Jellyfin = backup), so Plex proceeds now, not deferred.

---

## Verification evidence (SC-001..011)

Behavioural proof per `specs/006-media-stack/quickstart.md`. Fill in as each scenario
is run (mirrors the Phase-4 evidence style).

| SC | Scenario | Result | Evidence / notes |
|---|---|---|---|
| SC-001 | request→play | | |
| SC-002 | killswitch / no-leak | | |
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
