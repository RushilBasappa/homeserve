# Runbook — homeassistant (the home-automation hub)

A single **Dell-only**, **LAN/VPN-only** stack running the **HA Container** flavour of Home
Assistant (`ghcr.io/home-assistant/home-assistant`). This runbook is the bring-up order, the
first-run onboarding, the audits, and the exact diff for adding a Zigbee/Z-Wave radio later.

Upstream: <https://www.home-assistant.io/installation/linux#docker-compose> · Operating the fleet:
[[homeserve-ops-access]].

> This is an **added app** riding the existing platform (edge/DNS/TLS/Komodo), **not** a formal
> PLAN phase (cf. `wger`, `resume`, `basic-memory`).

---

## The one convention break, and why

Every other HTTP app in this lab runs on the shared `traefik` bridge network with no host ports
and Traefik **labels**. Home Assistant does **not** — it runs `network_mode: host`.

Home Assistant finds your devices by **listening to LAN broadcast and multicast**: mDNS/Bonjour
(HomeKit, ESPHome, Chromecast, AirPlay, Shelly), SSDP/UPnP (Sonos, Roku, smart TVs), and DHCP
sniffing. **Docker bridge networking drops all of it.** On bridge you get a working HA that
discovers essentially nothing and needs every device added by hand, by IP, forever. Upstream
documents host networking as the requirement for the Container install for exactly this reason.

Three consequences, all handled in code:

| Consequence | Handling |
|---|---|
| Traefik's **Docker** provider can't see a host-network container (it only discovers containers on the `traefik` network) | Routed by Traefik's **file** provider → `http://10.0.0.70:8123` — the same mechanism that fronts Mac stacks. See the `traefik-file-routes` config in `stacks/traefik/compose.yaml` and [[homeserve-traefik-mac-routing]]. |
| `:8123` is bound on the Dell's host | LAN/tailnet only, **never** router-forwarded; recorded in [`../CONVENTIONS.md`](../CONVENTIONS.md#ports). |
| HA rejects proxied requests unless told to trust the proxy | The seeded `configuration.yaml` ships the `http.use_x_forwarded_for` + `trusted_proxies` block. Without it Traefik's `X-Forwarded-For` makes HA return a hard **400**, not a warning. |

---

## Prerequisites

- Phase-3 edge live (Traefik + wildcard TLS + AdGuard + Homepage). `homeassistant.ragnaforge.xyz`
  resolves off the existing `*.ragnaforge.xyz` wildcard — **no new DNS record needed**.
- **No secrets.** HA has no bootstrap credentials: the owner account is created in the browser at
  onboarding, and per-integration tokens are entered in the UI and stored encrypted under
  `/config/.storage`. Nothing to add to `.mise.toml`, nothing to forward to Periphery, so **no
  `make sync-secrets` and no Periphery recreate** for this stack.
- `komodo/stacks.toml` has the `homeassistant` `[[stack]]` (server `ragnaforge-dell`); `RunSync` applied.
- **Port 8123 is free on the Dell.** Verify before deploying — host networking means a collision
  is a silent bind failure, not a Docker error:

  ```sh
  ssh ragnaforge-dell 'ss -lntp | grep :8123 || echo "8123 free"'
  ```

**Verify at deploy** (image-tag discipline): confirm the pinned tag in
`stacks/homeassistant/compose.yaml` is a current release. HA ships a **new minor every month**
(calver `YYYY.M.P`) and month releases regularly carry **breaking integration changes** — read the
notes before bumping, never bump blind: <https://www.home-assistant.io/blog/categories/release-notes/>
(`2026.7.4` == the `:stable`/`:latest` digest at write.)

---

## Bring-up order

1. **Deploy `traefik`.** The new route is an inline `configs:` block, and Komodo materialises inline
   configs **at container create** ([[homeserve-inline-configs-need-recreate]]). A **lone
   `DeployStack` was sufficient here** (verified 2026-07-27): the same commit also changed the
   `traefik` service's `configs:` **mount list**, so `compose up -d` saw a changed service
   definition and recreated the container. Prefer the lone deploy — `DestroyStack` + `DeployStack`
   back-to-back **races** because `/execute` is async and can leave the edge down.

   ⚠ **Content-only inline-config edits are different.** If you later change only the *content* of
   `traefik-file-routes` (e.g. add another host-network app) and touch nothing in the service block,
   `compose up -d` will **not** recreate — the container keeps serving the old routes while Komodo
   reports success. Force it: `ssh ragnaforge-dell 'docker rm -f traefik'` then `DeployStack`.
   (This is exactly what happened to `homepage` in step 4.)

   Confirm the route landed before moving on:

   ```sh
   ssh ragnaforge-dell 'docker exec traefik cat /dynamic/routes.yaml'
   ```

2. **Deploy `homeassistant` (cold)** via Komodo (`DeployStack`). `homeassistant-init` runs first,
   seeds `/config` (copy-if-absent), and exits `0`; HA then starts. **First boot is slow** — HA
   installs each integration's Python dependencies before the frontend answers, which is why the
   healthcheck has a 180s `start_period`. Watch it:

   ```sh
   ssh ragnaforge-dell 'docker logs -f homeassistant'      # wait for "Home Assistant initialized"
   ```

3. **Onboard.** Open **`https://homeassistant.ragnaforge.xyz`** and create the **owner account**
   (this is the only account creation gate — treat the password like Vaultwarden's). Set location,
   unit system and time zone, then accept or dismiss the devices HA has already discovered on the
   LAN — seeing a discovery list here is the proof that host networking is doing its job.

4. **Recreate `homepage`** so the Home Assistant tile appears on the front door. Its services list is
   an inline config and **only the content changed**, so a plain `DeployStack` is a silent no-op —
   observed live: Komodo reported success while `docker ps` still showed `Up 14 hours`. Force it:

   ```sh
   ssh ragnaforge-dell 'docker rm -f homepage'      # stateless — all config is inline
   # then DeployStack homepage, and verify the config actually landed:
   ssh ragnaforge-dell 'docker exec homepage grep -A3 "Home Assistant" /app/config/services.yaml'
   ```

   Verify by reading the file **inside the container**, not by curling `home.ragnaforge.xyz` —
   Homepage renders its tiles client-side, so the server HTML never contains the tile text.

---

## Editing configuration.yaml afterwards

`homeassistant-init` seeds `/config` **once** and never overwrites — after first boot, HA and you
own that directory, and the `configs:` block in the compose file is documentation, not the live
copy. The **File editor add-on does not exist in the Container flavour** (add-ons are a HA OS /
Supervised feature). Two ways in:

```sh
# quick edit in place
ssh ragnaforge-dell 'docker exec -it homeassistant vi /config/configuration.yaml'
# then: Developer Tools → YAML → "Check configuration", and restart HA from the UI
```

Or install the **Studio Code Server** / **File Editor** equivalents as a separate container
mounting the same volume — only worth it if you edit YAML often.

Changing the reverse-proxy block, the volume, or the image tag is a **repo** change
(`stacks/homeassistant/compose.yaml`), so the git copy stays the source of truth for the parts
that are load-bearing to the platform.

---

## Adding a Zigbee/Z-Wave radio (when the hardware exists)

Not wired today — this stack has **no `devices:` mapping**. When a USB coordinator (SkyConnect,
Sonoff ZBDongle-E, Z-Wave JS stick) is plugged into the Dell:

1. Find its **stable** path — never `/dev/ttyUSB0`, which renumbers across reboots:

   ```sh
   ssh ragnaforge-dell 'ls -l /dev/serial/by-id/'
   ```

2. Add the passthrough to the `homeassistant` service and redeploy:

   ```yaml
       devices:
         - /dev/serial/by-id/usb-<your-coordinator>:/dev/ttyACM0
   ```

3. Then either use HA's built-in **ZHA** / **Z-Wave JS** integration (nothing else to deploy), or
   stand up **Zigbee2MQTT + Mosquitto** as a separate stack — that path needs an MQTT broker and is
   a bigger change than a `devices:` line. Decide before pairing devices: **migrating between ZHA
   and Zigbee2MQTT means re-pairing every device.**

Matter/Thread additionally needs a Thread border router; `default_config:` already loads the Matter
integration, but the radio story is the same as above.

---

## Audits (the invariants)

- **Deliberate host binding, nothing more.** `ssh ragnaforge-dell 'ss -lntp | grep 8123'` shows HA
  listening; `docker ps` shows `homeassistant` with **no** published port mappings (host network
  means Docker publishes nothing — the bind is the process's own). **No** router forward targets
  8123. From off-LAN/off-VPN, `homeassistant.ragnaforge.xyz` does not serve.
- **Proxy trust actually configured.** `curl -sI https://homeassistant.ragnaforge.xyz` → 200 (or a
  redirect to `/auth/authorize`), **not** 400. A 400 here means the `http:` block is missing or the
  Docker bridge subnet isn't in `trusted_proxies`.
- **TLS**: Let's Encrypt wildcard cert, HTTP→HTTPS — the file-provider router reuses the default
  store, so no per-app cert was issued.
- **WebSockets work**: the HA frontend is WebSocket-driven — if the dashboard loads but shows
  "Connection lost", the route is proxying HTTP but not upgrading. Traefik does this natively; check
  the router, not HA.
- **Discovery works** (the whole reason for the convention break): Settings → Devices & Services
  shows **discovered** entries you never added by IP.
- **No committed secrets**: `git grep` finds **0** HA credentials — there are none by design; the
  owner password and every integration token live only in `/config/.storage` on the Dell.
- **Golden rule**: `docker volume ls` on the Dell shows `homeassistant_homeassistant-config`;
  **0** Home Assistant state on the Mac or under `/srv/nfs`.

---

## Backups gap (Phase 10)

`homeassistant-config` is the **entire instance** — configuration, the `.storage` device/entity/
area/user registries, integration tokens, and the SQLite recorder history. Losing it means
re-onboarding and, for Zigbee/Z-Wave, **re-pairing every device**. It is the highest-value single
volume added since Vaultwarden and is a **Phase-10 backup candidate**; the stand-up → Phase-10
window is a known, documented gap.

HA's own **Settings → System → Backups** can produce a `.tar` inside the volume as a stopgap — a
manual one before every version bump is cheap insurance given the monthly breaking-change cadence.
