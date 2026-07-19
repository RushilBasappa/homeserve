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
| 51820 | UDP | wg-easy | router-forwarded → Dell |

_(Table grows as stacks land in later phases.)_

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

Conventions:

- Config volumes are **local to the Dell** — do not put config on NFS (latency,
  locking) and never on the Mac.
- Shared media lives under the NFS export so any node (and the ARR stack +
  Jellyfin) sees the same `/media` layout.
- A stateless stack on the Mac keeps **no** persistent local state; if it needs
  state, it belongs on the Dell (see the golden rule).

Growth path when media outgrows the internal disk: **mergerfs + USB** on the
Dell (documented in Phase 4) — the NFS export path stays the same.

---

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
