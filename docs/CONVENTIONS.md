# Conventions

The single source of truth for how stacks are built in this repository. Every
phase and every new app follows these rules so the fleet stays consistent and
drift-free. When in doubt, this document wins.

Context and rationale live in [`../PLAN.md`](../PLAN.md); this file is the
operational "how."

---

## Golden rule: stateful data → the Dell

> **Every *stateful* app keeps its data on the Dell** (local volume or NFS).
> The Mac (`ragnaforge-mac`) runs only stateless / compute stacks.

Consequences: **one** backup source, and the Mac is disposable — lose it and
reassign its stacks with no data loss. Never put a database, config volume, or
media store on the Mac.

---

## Naming

| Thing | Rule | Example |
|---|---|---|
| **Stack** | lowercase app name; one directory under `stacks/` | `stacks/jellyfin/` |
| **Directory** | matches the stack name exactly | `stacks/vaultwarden/` |
| **Container** | the service name from `compose.yaml`; app name for the primary service | `jellyfin`, `gluetun` |
| **Host / node** | `ragnaforge-<role>` | `ragnaforge-dell`, `ragnaforge-mac` |
| **Hostname (URL)** | `<app>.ragnaforge.xyz`, app name as the subdomain | `jellyfin.ragnaforge.xyz` |
| **Volume** | `<app>-<purpose>` for named volumes | `immich-pgdata`, `jellyfin-config` |

Keep the app name identical across the directory, the container, the subdomain,
and the Homepage entry. One name, everywhere.

---

## Ports

- **Apps are not published to the host.** Traefik reaches them over the shared
  Docker network; do not add `ports:` mappings for HTTP services. Access is
  always via `https://<app>.ragnaforge.xyz`.
- **Publish a host port only when a non-HTTP protocol requires it** — e.g.
  wg-easy's `51820/udp` (router-forwarded), AdGuard's `53`, NFS. Document why in
  the stack's `compose.yaml`.
- **Admin UIs that must bind a port** (e.g. the wg-easy admin UI) bind to
  LAN/Tailscale only — **never** router-forwarded to the public internet.
- When a host port is unavoidable, keep it stable and record it here as stacks
  are added, so allocations don't collide.

| Port | Protocol | Stack | Exposure |
|---|---|---|---|
| 80, 443 | TCP | traefik | LAN / VPN (443 is the front door) |
| 53 | TCP/UDP | adguard | LAN (internal DNS) |
| 3000 | TCP | adguard | LAN/Tailscale admin — never router-forwarded |
| 51820 | UDP | wg-easy | **the one** public port — router-forwarded → Dell |
| 51821 | TCP | wg-easy | LAN/Tailscale admin — never router-forwarded |
| 6881 | TCP/UDP | arr (via gluetun) | **outbound only via Proton**; inbound = Proton's forwarded port. **Not** router-forwarded — no home-IP exposure |
| 45876 | TCP | beszel-agent-mac | **LAN only** — the Dell hub polls the Mac agent at `10.0.0.71:45876`; not router-forwarded, no public exposure |

_(Live as of Phase 3; Phase-5 rows added. Phase-6: the Tautulli (`8181`) and Beszel
hub (`8090`) UIs on the **Dell** publish **no** host ports — reached only via Traefik at
`tautulli`/`beszel.ragnaforge.xyz`. The Beszel **Mac** agent has no UI (nothing to route)
but binds `45876` on the host (Linux `network_mode: host`) so the Dell hub can poll it on the LAN. HTTP apps on the **Dell** publish **no**
host ports — reached only via Traefik labels. The Mac helpers publish LAN ports
because Traefik (Dell-only, label-based) can't see Mac containers; they are fronted
at `<app>.ragnaforge.xyz` by Traefik's **file** provider → `10.0.0.71:<port>` (see
`stacks/traefik/compose.yaml`). qBittorrent's peer traffic egresses via Proton, never
an inbound router forward. Table grows as stacks land.)_

---

## Traefik routing labels

Every HTTP app is exposed by attaching labels to its service — no manual proxy
config. Standard label set (Traefik + Cloudflare DNS-01 wildcard cert):

```yaml
services:
  <app>:
    image: ...
    networks: [traefik]          # shared external proxy network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.<app>.rule=Host(`<app>.ragnaforge.xyz`)"
      - "traefik.http.routers.<app>.entrypoints=websecure"
      - "traefik.http.routers.<app>.tls=true"
      # Wildcard cert *.ragnaforge.xyz is issued once via DNS-01; routers reuse it.
      - "traefik.http.services.<app>.loadbalancer.server.port=<container-port>"
```

Rules:

- Router / service names match the **stack name**.
- HTTP redirects to HTTPS globally (configured once on Traefik, not per app).
- The cert is the wildcard `*.ragnaforge.xyz` (DNS-01) — individual apps never
  request their own cert.
- `<container-port>` is the app's **internal** listen port, not a host port.

---

## Data placement

Two kinds of state, two homes — both on the Dell:

| Kind | Where | Notes |
|---|---|---|
| **Config / app state** (databases, settings, app config) | **Local named volume on the Dell** | Fast, backed up by Backrest. `<app>-config`, `<app>-pgdata`. |
| **Shared media** (movies, TV, photos) | **NFS on the Dell** (`/srv/nfs`, mounted on the Mac) | One media namespace both nodes can read. |

The shared-media namespace has a **fixed, materialized layout** (created by
`provision/tasks/storage-layout.yml`, Phase 4; contract in
`specs/005-storage/contracts/media-layout.md`). Phase 5 (ARR + Jellyfin) and
Phase 6 (Immich) mount these exact paths:

```text
/srv/nfs/                       owner rushil:rushil (1000:1000), dir mode 2775 (setgid)
├── media/movies/    Radarr, Jellyfin
├── media/tv/        Sonarr, Jellyfin
├── downloads/complete/    qBittorrent → Radarr/Sonarr import (hardlink source)
├── downloads/incomplete/  qBittorrent in-progress
└── photos/          Immich external-library / shared originals
```

`media/` and `downloads/` are under **one root on one filesystem**, so servarr
imports are instant hardlinks/atomic renames, not cross-device copies. The setgid
bit (`2775`) means every media container (run with `PUID=1000`/`PGID=1000`) creates
files the others can read/write.

Conventions:

- Config volumes are **local to the Dell** — do not put config on NFS (latency,
  locking) and never on the Mac. **Nothing config-related lives under `/srv/nfs`.**
- Shared media lives under the NFS export so any node (and the ARR stack +
  Jellyfin) sees the same layout above.
- A stateless stack on the Mac keeps **no** persistent local state; if it needs
  state, it belongs on the Dell (see the golden rule).

Growth path when media outgrows the internal disk: **mergerfs + USB** on the
Dell — see [`docs/runbooks/phase4-storage.md`](runbooks/phase4-storage.md#mergerfs--usb-growth-path).
The NFS export path (and every app mount) stays the same.

---

## Three configuration planes

Every change to the fleet lands in exactly one of **three separated planes**. Keeping
them apart is what makes the stack reproducible without one plane's concerns leaking
into another (spec FR-023a). Never wire an app during provisioning; never bake machine
setup into a compose file.

| Plane | Operates on | Where it lives | When it runs |
|---|---|---|---|
| **Machine** | the OS — Docker, NFS, sysctl, DNS-port freeing | `provision/` (Ansible over SSH) | pre-Docker, per host (`make provision`) |
| **Deployment** | Compose stacks — images, volumes, networks, Traefik labels | `komodo/stacks.toml` + `stacks/<app>/compose.yaml` | on deploy (Komodo, manual trigger) |
| **Application** | app HTTP APIs — the inter-app wiring (download clients, indexer sync, request/delete links) | `stacks/<app>/configure/` (idempotent Ansible `uri`) + Configarr | **post-deploy**, after apps are healthy with keys pinned |

Rules:

- **Machine plane is host setup only.** It never touches application config. Phase 5
  added no machine-plane work — it mounts the Phase-4 `/srv/nfs` tree as-is.
- **Deployment plane is declarative and secret-free.** Compose references secrets as
  `${VAR}` (from the mise-rendered Periphery env) and inlines non-secret Komodo
  variables as literals (Komodo does not interpolate `[[VAR]]` into git-pulled
  composes — mirror the value and cite `komodo/variables.toml`).
- **Application plane is co-located, post-deploy, and idempotent.** Wiring lives with
  its stack (e.g. `stacks/arr/configure/wire.yml`), runs only after the apps are up
  with their API keys pinned, GET-then-POSTs so a re-run is a no-op, and **fails
  loudly** on schema drift — never a silent, half-wired stack. No bespoke long-lived
  scripts; unmaintained declarative tools (e.g. Buildarr) are barred.

The deterministic API keys (set via env from mise) are the linchpin that lets the
application plane be fully declarative — every key is known before the wiring runs.

## New-app checklist

To add an app (`<app>`):

1. **Create the stack directory:** `stacks/<app>/` with a `compose.yaml`.
2. **Name consistently:** directory = stack = subdomain = Homepage entry (see
   [Naming](#naming)).
3. **Place data:** config → local volume on the Dell; shared media → NFS. Confirm
   the app is stateful → it runs on the Dell (golden rule). Stateless → may run
   on the Mac.
4. **Add Traefik labels** for `<app>.ragnaforge.xyz` (see
   [routing labels](#traefik-routing-labels)); attach the `traefik` network. No
   host `ports:` unless a non-HTTP protocol needs one.
5. **Wire up secrets:** add any required secret as a placeholder to
   [`../.mise.toml.example`](../.mise.toml.example) and reference it as
   `${VAR}` in the compose file — never a literal value.
6. **Register with Komodo:** declare the stack (name → directory → server) in
   [`../komodo/`](../komodo/) so Resource Sync picks it up.
7. **Add a Homepage entry** so it appears on the dashboard front door.
8. **Deploy** via Komodo (manual trigger or per-stack webhook) and verify
   `https://<app>.ragnaforge.xyz` loads with a valid cert.
9. **Back it up:** if it holds irreplaceable state, add it to Backrest (and a
   pre-backup DB dump if it runs a database).
10. **Document** anything app-specific in a runbook under `docs/` (Phase 11).
