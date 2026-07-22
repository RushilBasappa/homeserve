# Contract: Stack Inventory (stack × node × services × ports × volumes × secrets)

The interface this feature adds to the fleet. Komodo declares the stack in `komodo/stacks.toml`; the
HTTP **UI** is reached at `https://wger.ragnaforge.xyz` via Traefik → **nginx** (no host ports). All
state is in **Dell-local named volumes** (golden rule); nothing on `/srv/nfs` or the Mac. Access is
**LAN/VPN-only** — no router port-forward (FR-013).

## Stack

| Stack (name) | Compose file | Node | Services | Subdomain | Routed service | Config volumes | Notes |
|---|---|---|---|---|---|---|---|
| `wger` | `stacks/wger/compose.yaml` | Dell | web, nginx, celery_worker, celery_beat, db, cache | `wger` | **nginx** (:80) | `wger-static`, `wger-media`, `wger-pgdata`, `wger-celerybeat`, `wger-redis` | self-migrates on boot; nginx serves static/media; PowerSync excluded; heaviest lab stack |

- **One stack, six services** — `web` + `nginx` + `celery_worker` + `celery_beat` on the internal
  `wger` network; **only `nginx`** also joins the external `traefik` network for its route; `db`
  (`postgres:16`) + `cache` (`redis:7-alpine`) on the internal `wger` network only (never exposed).
- **Isolated** — its own directory, containers, volumes, and internal network; removing the stack leaves
  the rest of the fleet untouched.

## Ports

| Port | Proto | Service | Exposure | Why |
|---|---|---|---|---|
| (none published) | — | the UI | via Traefik→nginx only | "no host ports for HTTP" rule holds |
| 80 | TCP | nginx | internal (Traefik → 80) | serves `/static` + `/media`, proxies `/`→web; **the routed port** |
| 8000 | TCP | web | internal (`wger` net only) | Django/Gunicorn; health `wget :8000`; **not** routed directly |
| 5432 | TCP | db | internal (`wger` net only) | PostgreSQL — **not** published |
| 6379 | TCP | cache | internal (`wger` net only) | Redis (Django cache + Celery broker) — **not** published |

**No inbound router forward is added** — wger is not a public service (FR-013, SC-008).

## Secrets (`.mise.toml.example` placeholders — real values only in gitignored `.mise.toml`)

| Var | Used by | Notes |
|---|---|---|
| `WGER_SECRET_KEY` | web + celery `SECRET_KEY` | `openssl rand -hex 50` (Django secret key) |
| `WGER_POSTGRES_PASSWORD` | db `POSTGRES_PASSWORD` **and** web/celery DB password | `openssl rand -hex 32`; same value both places |

No JWT signing keys (mobile app / PowerSync is Out of Scope). Secrets are forwarded to the Periphery env
via `komodo/bootstrap/periphery.compose.yaml` `environment:` + `make sync-secrets` + a Periphery recreate
(see [[homeserve-ops-access]]), then referenced in compose as `${VAR}`.

## Non-secret config (inlined literals in the compose)

Komodo does not interpolate `[[VAR]]` into git-pulled compose, so non-secret config is inlined. **Exact
env-var spellings are taken verbatim from the pinned image's `config/prod.env` at implementation time;**
the documented wger keys are:

| Setting | Value | Purpose |
|---|---|---|
| `SITE_URL` | `https://wger.ragnaforge.xyz` | public origin |
| `ALLOWED_HOSTS` | `wger.ragnaforge.xyz` (+ localhost for healthcheck) | Django host allowlist |
| `CSRF_TRUSTED_ORIGINS` | `https://wger.ragnaforge.xyz` | CSRF (scheme required, Django 4+) |
| `X_FORWARDED_PROTO_HEADER_SET` | `X-Forwarded-Proto` | trust Traefik's proto |
| `USE_X_FORWARDED_HOST` | `True` | trust Traefik's host |
| `AXES_IPWARE_PROXY_COUNT` | `1` | one proxy hop (real client IP for brute-force lockout) |
| `DJANGO_PERFORM_MIGRATIONS` | `True` | migrate on boot |
| `DJANGO_COLLECTSTATIC_ON_STARTUP` | `True` | populate `wger-static` on boot |
| `DJANGO_DB_ENGINE` / `DJANGO_DB_HOST` / `DJANGO_DB_PORT` / `DJANGO_DB_DATABASE` / `DJANGO_DB_USER` | `…postgresql` / `db` / `5432` / `wger` / `wger` | DB connection |
| `POSTGRES_DB` / `POSTGRES_USER` | `wger` / `wger` | on the `db` service |
| `DJANGO_CACHE_BACKEND` / `DJANGO_CACHE_LOCATION` | Redis cache / `redis://cache:6379/1` | Django cache |
| `USE_CELERY` / `CELERY_BROKER` / `CELERY_BACKEND` | `True` / `redis://cache:6379/2` / `redis://cache:6379/2` | background jobs |
| `ALLOW_REGISTRATION` / `ALLOW_GUEST_USERS` | `False` / `False` | registration closed (R5) |
| exercise image/video sync flags | off/minimal | disk-friendly (R6) |

## Inline config (`configs: content:` — NOT a host bind)

| Config | Materialised at (verify target at deploy) | Content |
|---|---|---|
| `wger-nginx` | nginx conf.d (e.g. `/etc/nginx/conf.d/default.conf`) | trimmed upstream nginx.conf: `upstream wger { server web:8000; }`, `/static/`→`/wger/static/`, `/media/`→`/wger/media/`, `client_max_body_size 100M`, `listen 80;` — **no** `/ps/` PowerSync block |

Inline because Komodo can't resolve a relative `./config` bind ([[homeserve-beszel]]). **Editing this
block later requires a container recreate**, not just a redeploy ([[homeserve-inline-configs-need-recreate]]).

## Komodo declaration (`komodo/stacks.toml`)

One `[[stack]]` entry: `server = "ragnaforge-dell"`, `webhook_enabled = false` (manual deploys),
`repo = "RushilBasappa/homeserve"`, `file_paths = ["stacks/wger/compose.yaml"]`, tagged `apps`
(an added app riding the platform, not a formal PLAN phase — see spec Out of Scope).

## Traefik routing (canonical labels — on the **nginx** service)

```yaml
- "traefik.enable=true"
- "traefik.http.routers.wger.rule=Host(`wger.ragnaforge.xyz`)"
- "traefik.http.routers.wger.entrypoints=websecure"
- "traefik.http.routers.wger.tls=true"
- "traefik.http.services.wger.loadbalancer.server.port=80"
```

`web`/`celery_*`/`db`/`cache` carry **no** Traefik labels. HTTP→HTTPS redirect and the wildcard cert
come from the Phase-3 edge unchanged (FR-009, SC-006).

## Homepage (`stacks/homepage/compose.yaml`)

One tile in the **Apps** group (icon `wger.png`; `mdi-dumbbell` fallback; `href`
`https://wger.ragnaforge.xyz`). No native widget (FR-011, SC-006).
