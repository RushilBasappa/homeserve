# `arr` — the acquisition pipeline (one stack)

The download + acquisition backbone for the media phase, deployed as **one** Compose
stack on `ragnaforge-dell` because qBittorrent shares Gluetun's network namespace and
the PVRs are lifecycle-coupled to it (research R8). Everything a title needs between
a Seerr request and a hardlinked file in `/srv/nfs/media` lives here.

## Services

| Service | Role | UI |
|---|---|---|
| `gluetun` | Proton WireGuard egress + killswitch + NAT-PMP port forwarding | — |
| `qbittorrent` | download client, **inside gluetun's netns** | `qbittorrent.ragnaforge.xyz` |
| `prowlarr` | indexer manager; native app-sync → PVRs | `prowlarr.ragnaforge.xyz` |
| `radarr` | movie PVR | `radarr.ragnaforge.xyz` |
| `sonarr` | TV PVR | `sonarr.ragnaforge.xyz` |
| `bazarr` | subtitles | `bazarr.ragnaforge.xyz` |
| `unpackerr` | extracts archived releases for the PVRs | — |
| `configarr` | applies TRaSH quality profiles — its **own** stack (`stacks/configarr/`) | — (one-shot) |

## Egress model (the whole point)

Only qBittorrent egresses, and **only** through Proton. `qbittorrent` uses
`network_mode: "service:gluetun"`, so all of its traffic is inside the WireGuard
tunnel. Gluetun's default **killswitch** means a tunnel drop blocks it entirely — no
torrent packet ever reveals the home IP (SC-002). The PVRs reach qBit at
`http://gluetun:8080` on the `arr` network; the Web UI is fronted by Traefik on
gluetun's netns.

## Port-sync (native, no script)

Proton rotates the forwarded port. Gluetun's **native**
`VPN_PORT_FORWARDING_UP_COMMAND` POSTs the new port to qBittorrent's Web API over
localhost every time the tunnel comes up — no cron file, no sidecar (research R2).
For that localhost POST to succeed without credentials, qBittorrent must **bypass
authentication on localhost** (set once on first run — below).

## qBittorrent first-run (one-time, persists in the volume)

These live in `qbittorrent-config` on the Dell (not expressible from code):

1. `docker logs qbittorrent | grep -i password` → log in at the UI → set the Web UI
   password to `${QBIT_WEBUI_PASSWORD}`.
2. **Options → Web UI → "Bypass authentication for clients on localhost"** → enable
   (lets Gluetun's port-sync POST to `127.0.0.1:8080`).
3. Save path `/data/downloads/complete`, incomplete `/data/downloads/incomplete`
   (`/srv/nfs` is bind-mounted as `/data`).

## Hardlink imports

`qbittorrent`, `radarr`, `sonarr`, `bazarr`, `unpackerr` all mount the **whole**
`/srv/nfs` tree as `/data`. Because `downloads/` and `media/` are one filesystem
under one mount, PVR imports are instant **hardlinks**, not copies (SC-006) — seeding
continues with no duplicate disk use.

## Wiring (plane 3, post-deploy, idempotent)

`configure/wire.yml` establishes the edges no native tool covers, GET-then-POST so a
re-run is a no-op:

- Radarr/Sonarr → qBittorrent (download client)
- Prowlarr → Radarr/Sonarr (register apps → Prowlarr then native-syncs indexers)
- Bazarr → Radarr/Sonarr (subtitle source)
- Seerr → Radarr/Sonarr (gated on `-e seerr_enabled=true`, once Seerr is up)

```sh
cd stacks/arr/configure && mise exec -- ansible-playbook wire.yml
```

The API keys are pinned **deterministically** from mise
(`RADARR__AUTH__APIKEY=${RADARR_API_KEY}`, etc.), which is what makes the wiring
fully declarative. A schema-drift rejection after a major arr upgrade **fails the
play loudly** — never a silent unwired stack. **Buildarr is not used** (barred,
unmaintained).

## Quality from code (Configarr)

Configarr lives in its **own** stack — `stacks/configarr/` — not here. It's a
run-once job: it applies the TRaSH quality profiles/custom formats to Radarr/Sonarr
and exits 0 (a second run is a no-op — SC-009). Komodo judges a stack `unhealthy`
whenever any container isn't `running`, so keeping an intentionally-exited job inside
`arr` made the whole stack read unhealthy forever; splitting it out keeps `arr`
all-green. The configarr stack joins this stack's `arr_arr` network (external) to
reach the PVRs, so **deploy it after `arr` is up and the PVRs are healthy**.

The config is shipped **inline** via a top-level `configs:` block (materialised at
`/app/config/config.yml`), not a host bind: Komodo Periphery runs in a container with
`/etc/komodo` as a named volume, so a relative bind (`./configarr:/app/config`)
resolves to a host path the daemon can't find — Docker silently mounts an empty dir
and Configarr dies with "Config file not found". Inline `configs:` (the same pattern
`homepage`/`traefik` use) sidesteps this. The `!env RADARR_API_KEY` /
`!env SONARR_API_KEY` tags resolve from the service environment (keys forwarded from
mise via the Periphery agent).

## Image tags

All images are pinned to explicit tags (no `:latest`) per Diun/Phase-10 intent. Bump
deliberately and verify against the registry before deploying.

## State & placement

Config volumes (`qbittorrent-config`, `prowlarr-config`, `radarr-config`,
`sonarr-config`, `bazarr-config`) are **local named volumes on the Dell** (golden
rule). No app config lives on `/srv/nfs`. See `docs/runbooks/phase5-media.md` for
bring-up order and the verification evidence.
