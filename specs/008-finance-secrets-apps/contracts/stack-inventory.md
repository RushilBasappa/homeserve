# Contract: Stack Inventory (stacks × node × ports × volumes × secrets)

The interface this phase adds to the fleet. Komodo declares each stack in `komodo/stacks.toml`; every
HTTP **UI** is reached at `https://<name>.ragnaforge.xyz` via Traefik (no host ports). All state is in
**Dell-local named volumes** (golden rule); nothing on `/srv/nfs` or the Mac. Access is **LAN/VPN-only**
— no router port-forward (FR-015).

## Stacks

| Stack (name) | Compose file | Node | Services | Subdomain | Config volumes | Notes |
|---|---|---|---|---|---|---|
| `vaultwarden` | `stacks/vaultwarden/compose.yaml` | Dell | vaultwarden | `vaultwarden` | `vaultwarden-data` | password server; signups off; Argon2 admin token; E2E-encrypted |
| `actual` | `stacks/actual/compose.yaml` | Dell | actual | `actual` | `actual-data` | budgeting; plain HTTP behind Traefik; login set in-app (no secret) |
| `sure` | `stacks/sure/compose.yaml` | Dell | web, worker, db, redis | `sure` | `sure-pgdata`, `sure-storage`, `sure-redis` | net-worth (Maybe fork); self-migrates on boot; heaviest 7a stack |

- **Three isolated stacks** — own directory, containers, volumes (Sure adds an internal network). Removing
  one (e.g. the Actual-vs-Sure trial loser) leaves the others running (FR-014, SC-009).
- **Sure is one compose, four services**: `web` + `worker` on the shared `traefik` + internal `sure`
  networks; `db` (`postgres:16`) + `redis` (`redis:7-alpine`) on the internal `sure` network only (never
  exposed). Only `web` carries a Traefik router.

## Ports

| Port | Proto | Stack/Service | Exposure | Why |
|---|---|---|---|---|
| (none published for HTTP) | — | all three UIs | via Traefik only | "no host ports for HTTP" rule holds |
| 80 | TCP | vaultwarden | internal (Traefik → 80) | Vaultwarden HTTP (Docker default; **3012 removed**, not published) |
| 5006 | TCP | actual | internal (Traefik → 5006) | Actual HTTP |
| 3000 | TCP | sure `web` | internal (Traefik → 3000) | Rails/Puma; health `/up` |
| 5432 | TCP | sure `db` | internal (`sure` net only) | PostgreSQL — **not** published |
| 6379 | TCP | sure `redis` | internal (`sure` net only) | Redis/Sidekiq — **not** published |

**No inbound router forward is added** — none of these are public services (FR-015, SC-006).

## Secrets (`.mise.toml.example` placeholders — real values only in gitignored `.mise.toml`)

| Var | Used by | Notes |
|---|---|---|
| `VAULTWARDEN_ADMIN_TOKEN` | vaultwarden `ADMIN_TOKEN` | Argon2 PHC hash from `vaultwarden hash`; **double `$`→`$$`** in the compose `environment:` block |
| `SURE_SECRET_KEY_BASE` | sure web + worker | `openssl rand -hex 64` |
| `SURE_POSTGRES_PASSWORD` | sure db + web + worker | `openssl rand -hex 32` |

Actual adds **no** secret (server login password is set in-app on first run). Secrets are forwarded to
the Periphery env via `komodo/bootstrap/periphery.compose.yaml` `environment:` + `make sync-secrets` +
a Periphery recreate (see [[homeserve-ops-access]]), then referenced in compose as `${VAR}`.

## Non-secret config (inlined literals in each compose)

Komodo does not interpolate `[[VAR]]` into git-pulled compose, so non-secret config is inlined:

| Setting | Value | Stack |
|---|---|---|
| `DOMAIN` | `https://vaultwarden.ragnaforge.xyz` | vaultwarden |
| `SIGNUPS_ALLOWED` | `false` (after initial account) | vaultwarden |
| `ENABLE_WEBSOCKET` | `true` (default; served on :80) | vaultwarden |
| `APP_DOMAIN` | `sure.ragnaforge.xyz` | sure |
| `SELF_HOSTED` | `true` | sure |
| `RAILS_ASSUME_SSL` | `true` (TLS terminated at Traefik) | sure |
| `REDIS_URL` | `redis://redis:6379/1` | sure |
| `DB_HOST`/`DB_PORT`/`POSTGRES_DB`/`POSTGRES_USER` | `db`/`5432`/`sure`/`sure` | sure |
| `ONBOARDING_STATE` | `open` → `closed` after first account | sure |
| `dns` | `8.8.8.8, 1.1.1.1` (web+worker; avoids IPv6 sync hang) | sure |

## Komodo declaration (`komodo/stacks.toml`)

Three `[[stack]]` entries, all `server = "ragnaforge-dell"`, `webhook_enabled = false` (manual deploys),
tagged `phase-7a` / `apps`:

- `vaultwarden` → `file_paths = ["stacks/vaultwarden/compose.yaml"]`
- `actual` → `file_paths = ["stacks/actual/compose.yaml"]`
- `sure` → `file_paths = ["stacks/sure/compose.yaml"]`

## Traefik routing (per UI, canonical labels)

Each UI carries the canonical label set (as every Phase-3/5 app does), differing only by name and port:

```yaml
- "traefik.enable=true"
- "traefik.http.routers.<name>.rule=Host(`<name>.ragnaforge.xyz`)"
- "traefik.http.routers.<name>.entrypoints=websecure"
- "traefik.http.routers.<name>.tls=true"
- "traefik.http.services.<name>.loadbalancer.server.port=<80|5006|3000>"
```

Sure's `db`/`redis` carry **no** Traefik labels. HTTP→HTTPS redirect and the wildcard cert come from
the Phase-3 edge unchanged (FR-012, SC-005). Vaultwarden's WebSocket `Upgrade` is forwarded by Traefik
automatically — no extra router.

## Homepage (`stacks/homepage/compose.yaml`)

Three tiles added to the **Apps** group (icons `vaultwarden.png`, `actual.png`, `sure.png`; `href` to
each `https://<app>.ragnaforge.xyz`). No native widgets (FR-013, SC-005).
