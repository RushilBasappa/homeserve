# Ragnaforge Home Server — Master Plan

> A reproducible, low-maintenance, self-hosted home server across two Debian
> laptops, managed with Docker Compose + Komodo, reachable privately (Tailscale)
> and by family/friends (self-hosted WireGuard), with valid HTTPS on every app.
>
> **Design north star:** minimal custom code, off-the-shelf tools, nothing that
> silently goes outdated, and a setup a competent friend could reproduce from
> this document.

---

## 1. Overview

| | |
|---|---|
| **Domain** | `ragnaforge.xyz` (on Cloudflare) |
| **Orchestration** | Docker Compose, managed by **Komodo** (git-synced, deploy-on-demand) |
| **Nodes** | `ragnaforge-dell` (10.0.0.70) — data + compute · `ragnaforge-mac` (10.0.0.71) — compute |
| **Secrets** | `mise` (`.mise.toml`, gitignored) → rendered env for Komodo |
| **VPN #1 (you)** | **Tailscale** — personal remote access (already installed) |
| **VPN #2 (family/friends + Fire TV)** | **wg-easy** on the Dell + router UDP port-forward + Cloudflare DDNS |
| **Edge / TLS** | **Traefik** + Let's Encrypt wildcard cert via Cloudflare **DNS-01** |
| **Internal DNS** | **AdGuard Home** — `*.ragnaforge.xyz → 10.0.0.70` + network ad-blocking |
| **Storage** | Dell internal disk as **NFS anchor**; mergerfs + USB as the future growth path |

### Hardware reality (measured)

| | ragnaforge-dell | ragnaforge-mac |
|---|---|---|
| CPU | Intel i3-10110U · 2c/4t (UHD QuickSync) | Intel i5-5257U · 2c/4t (Iris 6100 QuickSync) |
| RAM | 7.5 GB | 7.7 GB |
| Disk | 238 GB NVMe | 113 GB SSD |
| Network | built-in gigabit (`eno1`) | **USB** gigabit dongle |
| Role | NFS server, Traefik, VPN endpoint, all stateful apps | stateless compute offload |

### Network facts
- **Public IP** `76.102.108.83` (Comcast, dynamic) — **not** behind CGNAT, so port-forwarding works.
- Router LAN gateway `10.0.0.1`; LAN `10.0.0.0/24`.
- IPv6 available but VPN endpoint uses IPv4 + DDNS for universal reachability.

---

## 2. Architecture

```
                        Internet
                           │
        ┌──────────────────┼───────────────────┐
   Tailscale (you)   Router :51820/udp     Cloudflare
        │            forward → Dell         DNS + DDNS + DNS-01 certs
        │                  │
   ═══════════════════ 10.0.0.0/24 (home LAN) ═══════════════════
        │                                    │
   ragnaforge-dell (10.0.0.70)          ragnaforge-mac (10.0.0.71)
   • Komodo Core + Periphery            • Komodo Periphery
   • Traefik (edge TLS)                 • stateless app stacks
   • AdGuard Home (internal DNS)
   • wg-easy (VPN #2)  + Cloudflare DDNS
   • NFS server  /srv/nfs
   • all stateful apps + backups + monitoring
```

**Golden rule:** every *stateful* app keeps its data on the Dell (local volume
or NFS). The Mac runs only stateless/compute stacks. → one backup source, and
the Mac is disposable.

### How a request resolves

| Name | Resolves to | Reachable when |
|---|---|---|
| `vpn.ragnaforge.xyz` | home public IP (DDNS) | always (public) — WireGuard handshake target |
| `*.ragnaforge.xyz` | `10.0.0.70` (Traefik) | only on LAN or VPN |

Typing `https://jellyfin.ragnaforge.xyz` on the VPN → resolves to `10.0.0.70`
→ tunnels to Dell → Traefik (valid wildcard cert) → Jellyfin container.

---

## 3. Design principles (the answers to recurring questions)

- **Git workflow (hybrid, no forced auto-push):** the git repo is the source of
  truth. Komodo syncs from it, and you deploy on a **manual trigger** (UI/CLI) —
  or opt into webhook auto-deploy per stack. Git is storage + history, not a
  deploy button you're forced to press.
- **Add / remove a laptop:** install the Komodo **Periphery** agent on the new
  host, register it, assign stacks (declared in git). Remove one → reassign its
  stacks. No re-architecture. Stateful stacks stay on the Dell.
- **Backups from "both laptops":** state is centralized on the Dell, so there is
  **one** backup source. Only if some state must live on the Mac do we add a
  second Restic agent.
- **Swapping the VPN later (wg-easy → Netbird):** the VPN is an isolated stack;
  apps/proxy/DNS don't depend on it. Stand up the replacement alongside,
  re-onboard devices, remove the old stack + port-forward. Clean drop-in.
- **Secrets never leak into the shareable report:** real values live only in the
  gitignored `.mise.toml`; the repo ships `.mise.toml.example` with placeholders.

---

## 4. Phases

Each phase is independently verifiable. Dependencies noted.

### Phase 0 — Foundation & repo scaffolding
**Objective:** the repo skeleton, conventions, and secret handling that
everything else drops into.
- Repo layout: `stacks/` (one dir per Compose stack), `provision/` (lean
  Ansible), `komodo/` (resource-sync definitions), `docs/`, `PLAN.md`, `README.md`.
- `.mise.toml.example` (placeholders) + `.gitignore` (`.mise.toml`, `.env`, generated).
- `docs/CONVENTIONS.md`: naming, ports, labels, "stateful → Dell" rule, the
  new-app checklist.
- README skeleton that *is* the shareable report (grows each phase).
- **Deliverable:** clonable repo that documents itself. **Depends on:** none.

### Phase 1 — Migration & host provisioning
**Objective:** two clean Docker hosts, existing data preserved.
- **Preserve first:** snapshot `/srv/nfs` (103 GB media + Immich) and export any
  current app config worth keeping (Vaultwarden, Actual, HA, *arr) before teardown.
- Tear down the existing **k3s** cluster on both nodes.
- Lean **Ansible** (≈ a handful of tasks, not the old 7 roles): Docker Engine,
  NFS packages/mounts, sysctl (IP forwarding), user/SSH baseline.
- Verify **Tailscale** on both nodes.
- **Tools:** Ansible, Docker Engine. **Deliverable:** `make provision` → two
  Docker hosts. **Depends on:** Phase 0.

### Phase 2 — Orchestration (Komodo)
**Objective:** central, git-synced management of both nodes.
- **Komodo Core** on the Dell (web UI + API) + **Komodo Periphery** on both nodes.
- Connect Komodo to the git repo (**Resource Sync**); define Servers + Stacks.
- Secret injection: `mise`-rendered env → Komodo variables/secrets.
- Establish the deploy workflow (manual trigger; optional per-stack webhook).
- **Deliverable:** deploy any stack from the UI/CLI. **Depends on:** Phase 1.

### Phase 3 — Edge, DNS & TLS
**Objective:** every app at `https://<name>.ragnaforge.xyz` with a real cert.
- **Traefik** (Docker-label routing, HTTP→HTTPS redirect).
- Let's Encrypt **wildcard** `*.ragnaforge.xyz` via Cloudflare **DNS-01**.
- **AdGuard Home** as internal resolver → `*.ragnaforge.xyz → 10.0.0.70`
  (bonus: LAN-wide ad-blocking); pushed to VPN clients to beat DNS-rebind protection.
- **Cloudflare DDNS** container → keeps `vpn.ragnaforge.xyz` on the current public IP.
- **Homepage** dashboard as the front door.
- **Deliverable:** `https://home.ragnaforge.xyz` loads with valid TLS.
  **Depends on:** Phase 2.

### Phase 4 — Storage ✅
**Objective:** one media/config namespace, backup-friendly.
- Dell **NFS** server (`/srv/nfs`), mounted on the Mac.
- Volume conventions: config volumes local to the host; shared media on NFS.
- Enforce the "stateful → Dell" rule.
- Document the **mergerfs + USB** growth path (reuse `usb-automount` idea) for
  when media outgrows the internal disk.
- **Deliverable:** consistent `/media` + config layout. **Depends on:** Phase 1.

### Phase 5 — Media stack (ARR + Jellyfin & Plex)
**Objective:** downloadable, interconnected media over a VPN egress.
- **Gluetun** (WireGuard egress + killswitch) → **qBittorrent** routed through it.
- **Prowlarr** → **Radarr** / **Sonarr** / **Bazarr** (subtitles).
- **Jellyfin** & **Plex** (both QuickSync HW transcode, one shared `/srv/nfs/media`
  library) + **Jellyseerr** (requests).
- **Interconnection without custom API roles:** Prowlarr's built-in app-sync +
  **Configarr** container for TRaSH quality profiles/custom formats.
- **Deliverable:** request → download (via VPN) → library → play.
  **Depends on:** Phases 3, 4.

### Phase 6 — Media & system stats
**Objective:** see the audience and the load — who's watching what, and whether
the box can take it. Dashboards/visibility only; push alerting lands in Phase 9.
- **Tautulli** (Plex watch stats) — per-user history, now-playing, per-stream
  bandwidth, and the **direct-play vs transcode** breakdown (the number that
  tells you when Plex is cooking the i3's iGPU/CPU). Talks to Plex read-only via
  the server token; its SQLite history DB → **Dell** (golden rule). Traefik-routed
  at `tautulli.ragnaforge.xyz`; Homepage now-playing widget. (Plex is the primary
  server — the earlier Jellyfin-stats tool *Jellystat* was dropped as unused.)
- **Beszel** (host + container metrics) — a hub on the Dell + a lightweight agent
  on the Mac give **one fleet view**: CPU, RAM, disk usage %, network, temps, and
  per-container stats, with thresholds. Chosen over Netdata (heavier, cloud-nudgey)
  and Prometheus/Grafana (multi-GB — deferred) to fit the 7.5 GB nodes. Traefik-
  routed at `beszel.ragnaforge.xyz`; Homepage widget. (Disk *health*/SMART via
  Scrutiny intentionally skipped for now — Beszel's usage % is enough.)
- Notifications are **deferred**: Beszel thresholds → **ntfy** push wiring lands in
  Phase 9 (Alerting). This phase is dashboards only.
- **Deliverable:** open one page and see current streams + per-node load.
  **Depends on:** Phases 3, 5.

### Phase 7 — Apps
**Objective:** the rest of the lab.
- **Immich** (photos), **Home Assistant**, **Actual Budget**, **Vaultwarden**
  (passwords), **n8n** (automation).
- Each: Compose stack + Traefik labels + Homepage entry + config volume on Dell.
- **Deliverable:** all apps at `https://<name>.ragnaforge.xyz`.
  **Depends on:** Phase 3.

### Phase 8 — VPN #2 (wg-easy)
**Objective:** family/friends + Fire TV on the network, easy onboarding.
- **wg-easy** stack on the Dell; router forwards **UDP 51820 → 10.0.0.70**;
  admin UI bound to LAN/Tailscale only (never forwarded).
- Dell as **subnet router** (IP forwarding) → clients reach `10.0.0.0/24`.
- Client configs use `Endpoint = vpn.ragnaforge.xyz:51820`.
- **Fire TV onboarding:** deliver `.conf` via "Send Files to TV" / USB, import in
  the WireGuard app (no QR — no camera).
- Optional **nftables** rule fencing friend clients to media (Jellyfin) only.
- **Deliverable:** a remote device joins from a fresh `.conf` and reaches
  `https://jellyfin.ragnaforge.xyz`. **Depends on:** Phases 3, 7.

### Phase 9 — Alerting (up/down + push)
**Objective:** know when a disk fills or an app dies — on your phone.
- **Uptime Kuma** (service up/down probes) → **ntfy** (self-hosted push to phone app).
- Wire alert rules into ntfy: **Beszel** thresholds from Phase 6 (disk > 85%,
  sustained high load), any Uptime-Kuma-monitored service down, optionally select
  Tautulli events.
- (Prometheus/Grafana intentionally skipped — too heavy for 7.5 GB nodes; optional later.)
- **Deliverable:** a test alert reaches your phone. **Depends on:** Phases 3, 6.

### Phase 10 — Backups
**Objective:** protect the irreplaceable (photos, passwords, finances, configs).
- **Backrest** (Restic GUI); local repo now, offsite (Backblaze B2) as a one-line add.
- Pre-backup **DB dumps** for Immich (Postgres) and Vaultwarden.
- Schedules + retention; documented **restore** procedure.
- **Deliverable:** a verified restore of one app's config. **Depends on:** Phase 7.

### Phase 11 — Auto-update & maintenance
**Objective:** stay current without surprise breakage.
- **Diun** — notifies (via ntfy) when a new image is available.
- Update deliberately via **Komodo** redeploy (not blind `:latest` auto-pull).
- Optional **Renovate** on the git repo for pinned versions.
- **Deliverable:** update notifications + a documented update flow.
  **Depends on:** Phases 2, 9.

### Phase 12 — Documentation & handoff (the shareable report)
**Objective:** the reproduce-from-scratch artifact.
- Finalize `README.md` + `docs/runbooks/` (indexers, media libraries, per-app setup).
- "Stand it up from zero" guide; secrets handled via `.mise.toml.example`.
- Optional: publish a polished web version.
- **Deliverable:** a document a friend could follow end-to-end.
  **Depends on:** all.

### Phase 13 — Migrate to the Mac Mini (future)
**Objective:** consolidate the whole server onto one powerful box (2018 Intel Mac
Mini, 32 GB RAM, 2 TB) that *also* serves as a macOS desktop (Illustrator,
Photoshop, general-purpose apps) — removing the RAM and storage constraints that
shaped Phases 1–12.

**Why this is a migration, not a rewrite:** the Compose + Komodo design is
host-portable. The Mac Mini's Linux VM is just another Debian + Docker + Komodo
node, so moving in reuses the same "add a node" workflow from §3.

**Target shape:**
```
        Mac Mini 2018 (Intel, 32 GB, 2 TB)
   ┌───────────────────────────────────────────┐
   │  macOS (host) — Adobe + desktop  (~16 GB)  │
   │  ┌──────────────────────────────────────┐ │
   │  │ Debian VM "ragnaforge-mini" (~16 GB) │ │
   │  │  Docker + Komodo + all stacks        │ │
   │  │  bridged NIC → real LAN IP 10.0.0.72 │ │
   │  └──────────────────────────────────────┘ │
   └───────────────────────────────────────────┘
```

**Steps:**
1. **VM host:** install a bridged Linux VM (Debian) via VMware Fusion (free) /
   Parallels / UTM. Bridged NIC → the VM gets its own `10.0.0.x` LAN IP and
   behaves exactly like the current Debian nodes. Allocate ~16 GB RAM to the VM,
   leave ~16 GB for macOS + Adobe.
2. **Keep the desktop usable:** disable system sleep (Energy Saver / `caffeinate`)
   so the VM stays up; accept that macOS/Adobe update reboots briefly stop the server.
3. **Join the fleet:** install Docker + **Komodo Periphery** in the VM, register
   it in Komodo as `ragnaforge-mini`.
4. **Move the data:** `rsync` `/srv/nfs` (media + photos) onto the Mac Mini's 2 TB
   virtual disk.
5. **Reassign stacks:** point the stacks at the new node in Komodo; flip Traefik /
   AdGuard `*.ragnaforge.xyz` and the router port-forward to `10.0.0.72`.
6. **Collapse to single-node:** with everything on one box, **retire NFS** —
   containers use local volumes on the 2 TB disk. Retire the laptops or keep them
   as spare Komodo compute nodes.

**What gets simpler after this phase:**
- **No NFS** — single-node local volumes.
- **No RAM juggling / manual stack placement** — 32 GB fits the whole stack.
- **No storage constraint** — 2 TB vs the laptops' ~238 GB.
- Multi-node "add/remove device" concerns become optional, not load-bearing.

**Caveats:**
- **Jellyfin HW transcode:** Intel iGPU passthrough into a Linux VM on a macOS
  host generally doesn't work → rely on client **direct-play** (common) or CPU
  transcode (fine for 1–2 1080p streams). Escape hatch if ever needed: run
  Jellyfin natively on macOS (VideoToolbox), keeping the rest in the VM.
- **Shared box:** the server and your workstation now share fate for reboots/crashes.

- **Deliverable:** the full stack running in the Mac Mini VM, laptops retired or
  demoted to spares, macOS free for Adobe/desktop use. **Depends on:** a stable
  Phases 1–12 build to migrate from.

---

## 5. Tool summary (best-in-class per stage)

| Concern | Tool |
|---|---|
| Orchestration | Komodo + Docker Compose |
| Provisioning | Ansible (lean) |
| Reverse proxy / TLS | Traefik + Let's Encrypt DNS-01 (Cloudflare) |
| Internal DNS / adblock | AdGuard Home |
| Dynamic DNS | Cloudflare DDNS |
| VPN (personal) | Tailscale |
| VPN (family/friends) | wg-easy (self-hosted WireGuard) |
| Media server | Jellyfin (+ Jellyseerr) |
| ARR | Prowlarr, Radarr, Sonarr, Bazarr |
| Download client + egress | qBittorrent behind Gluetun |
| ARR config | Configarr (TRaSH) + Prowlarr app-sync |
| Photos | Immich |
| Home automation | Home Assistant |
| Finance | Actual Budget |
| Passwords | Vaultwarden |
| Automation | n8n |
| Dashboard | Homepage |
| Media stats (Plex) | Tautulli |
| Host/container metrics | Beszel |
| Uptime (up/down) | Uptime Kuma |
| Alerts | ntfy |
| Backups | Backrest (Restic) |
| Update notify | Diun (+ optional Renovate) |
| Secrets | mise |

---

## 6. Prerequisites / open items
- Cloudflare **API token** (DNS-01 + DDNS) — present in `.mise.toml`.
- Router admin access to add the **UDP 51820** port-forward.
- A commercial VPN with **WireGuard** credentials for Gluetun egress — present in `.mise.toml`.
- **Rotate** the Tailscale auth key + Cloudflare token (surfaced during planning).
- Decide at build time: enforce **nftables** friend-restriction, or trust full-LAN access.

### Deferred — do once the full stack is running & stable
- **Spread load across both nodes to use the Mac's RAM/CPU.** No failover goal — just
  distribute stacks (Komodo pins each to a node via `server =`; reversible anytime, no
  data migration since files stay on the Dell's `/srv/nfs`).
  - Candidate split for media: **display (Jellyfin) stays on the Dell** (near storage);
    move **download/automation (qBittorrent+Gluetun, *arr) to `ragnaforge-mac`** — they
    reach `/srv/nfs` over the existing Dell→Mac NFS mount.
  - Rules when moving an app to the Mac: (1) mount `/srv/nfs` at the **same container
    path on both nodes** (*arr store absolute paths); (2) keep `downloads/` + `media/`
    under the **one NFS mount** so qBit→Radarr→Jellyfin **hardlinks** stay on one
    filesystem; (3) Mac apps can't join the Dell's `traefik` Docker network — publish a
    host port and front any web UI via a **Traefik file-provider route → 10.0.0.71:port**
    (see [[homeserve-traefik-mac-routing]]).
