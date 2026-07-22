# Phase 0 — Research: Self-host wger

The technical decisions behind the wger stack and why they were made. wger is off-the-shelf and
standalone; the "research" is confirming the topology, images, ports, env, static-file handling,
behind-proxy config, cold-deploy self-migration, and registration lockdown so the stack is reproducible
and correct — and pinning what the upstream `wger-project/docker` production compose does vs. what we
deliberately trim. Facts checked against upstream (`wger-project/docker`, `docs/production`) on
2026-07-22 — re-verify version tags and the exact env-var/mount names at deploy (Diun/Phase-10 intent).

---

## R1 — Topology: which services, and which we trim

**Decision.** Run **six** services in one stack on the Dell: `web` (Django/Gunicorn), `nginx` (reverse
proxy + static/media), `celery_worker`, `celery_beat`, `db` (PostgreSQL), `cache` (Redis). **Trim** the
upstream **PowerSync** service (and the `/ps/` nginx block) and every optional integration.

**Rationale.**
- The upstream production compose runs an application server, a reverse proxy, a database, a caching
  server, and a Celery queue — plus an optional PowerSync service for the mobile app's offline sync.
- **nginx is mandatory** (see R2). `web` runs the app (`/start`), and the **same image** runs the
  Celery worker (`/start-worker`) and beat scheduler (`/start-beat`) — the exercise/ingredient DB sync
  and API-cache jobs (R6).
- **PowerSync is excluded** because the spec puts the mobile app / offline sync Out of Scope; excluding
  it also drops its JWT signing keys and the nginx `/ps/` proxy location, keeping the stack lean on the
  7.5 GB Dell. It can be added later as a separate change without disturbing the web app.

**Alternatives considered.** Upstream's SQLite `dev` compose (rejected — not production; single-file DB,
no Celery/nginx story). Running PowerSync now (rejected — out of scope, extra service + JWT keys +
disk). A `web`-only stack with Django serving its own static via WhiteNoise (rejected — upstream ships
and requires the nginx static-serving path; deviating invites the unstyled-site failure).

---

## R2 — nginx is mandatory, and its config ships INLINE

**Decision.** Route Traefik to the **`nginx`** service (:80), not to `web`. nginx serves `/static/`
(alias `/wger/static/`) and `/media/` (alias `/wger/media/`) from the shared volumes and `proxy_pass`es
everything else to `upstream wger { server web:8000; }`. Ship the nginx config **inline** via Compose
top-level `configs: content:` (materialised in the container), **not** a `./config/nginx.conf` bind.

**Rationale.**
- Upstream is explicit: *you need to keep this nginx service … otherwise the static files will not be
  served correctly.* Django in production does not serve its own static/media; nginx does, from volumes
  that `web` populates on boot (`collectstatic`) and that users upload into (`/media`). Pointing Traefik
  at `web:8000` directly yields a **served-but-unstyled** site and **404 media** — the signature wger
  self-host failure and exactly spec Edge Case #1 / FR-005 / SC-004.
- **Inline config, not bind (the load-bearing infra decision):** Komodo pulls the compose from a git
  clone and Periphery runs `docker compose` with `/etc/komodo` as a named volume, so a relative
  `./config/nginx.conf` bind resolves to a host path the daemon can't find → an **empty mount**. This is
  the same failure that forced homepage, configarr, traefik, and beszel to inline their config
  ([[homeserve-beszel]], [[homeserve-inline-configs-need-recreate]]). So the nginx.conf is a top-level
  `configs:` block with `content: |`, referenced by the `nginx` service and targeted at the nginx conf.d
  path (upstream mounts it into nginx; **verify the exact target — `/etc/nginx/conf.d/default.conf` — at
  deploy**). We ship a **trimmed** copy: upstream's `upstream wger { server web:8000; }`, the `/static/`
  and `/media/` alias blocks, `client_max_body_size 100M`, `listen 80;` — **without** the `/ps/`
  PowerSync location (R1).
- **Trade-off:** editing an inline `configs:` block later needs a container **recreate**
  (DestroyStack+DeployStack), not just a redeploy ([[homeserve-inline-configs-need-recreate]]) — noted in
  the stack header and runbook.

**Alternatives considered.** Baking a custom nginx image with the config (rejected — an image to build
and host for a three-block config; inline is git-declared and simpler). Serving static from Django via
WhiteNoise (rejected — see R1).

---

## R3 — Behind-proxy correctness (Traefik terminates TLS)

**Decision.** Tell Django its public HTTPS origin and to trust Traefik's forwarded headers:
`SITE_URL=https://wger.ragnaforge.xyz`, `ALLOWED_HOSTS` including `wger.ragnaforge.xyz`,
`CSRF_TRUSTED_ORIGINS=https://wger.ragnaforge.xyz`, `X_FORWARDED_PROTO_HEADER_SET` (trust
`X-Forwarded-Proto`), `USE_X_FORWARDED_HOST=True`, and set the reverse-proxy count
(`AXES_IPWARE_PROXY_COUNT=1`) so brute-force IP detection sees the real client. All inlined literals.

**Rationale.**
- Traefik terminates TLS and forwards plain HTTP to nginx→web. Without the public origin and forwarded
  proto/host, Django (a) rejects the request as a disallowed host, (b) **CSRF-fails logins/forms**
  (Django 4+ requires the scheme in `CSRF_TRUSTED_ORIGINS`), and (c) builds `http://`/internal redirect
  and asset URLs — spec Edge Case #2 / FR-010 / SC-006. This is the same class of setting as Sure's
  `RAILS_ASSUME_SSL=true`, adapted to Django's variable names.
- `AXES_IPWARE_PROXY_COUNT` matches the single Traefik hop so django-axes attributes attempts to the
  real client IP, not the proxy.
- The **exact env-var spellings** are taken verbatim from upstream `config/prod.env` at implementation
  time; the names above are the documented wger keys — confirm against the pinned image's `prod.env`.

**Alternatives considered.** `RECAPTCHA`/proxy-header SSO auth (out of scope — off). Forcing SSL inside
Django (rejected — the edge already terminates TLS; double-handling risks redirect loops).

---

## R4 — Cold-deploy self-migration & start ordering

**Decision.** `web` runs migrations and collects static on boot
(`DJANGO_PERFORM_MIGRATIONS=True`, `DJANGO_COLLECTSTATIC_ON_STARTUP=True`) and `depends_on` **healthy**
`db` + `cache`. `nginx depends_on web` (healthy); `celery_worker depends_on web` (healthy);
`celery_beat depends_on celery_worker` (healthy). Healthchecks: `db` = `pg_isready`, `cache` =
`redis-cli ping`, `web` = `wget http://localhost:8000` (upstream), `celery_worker` =
`celery -A wger inspect ping`.

**Rationale.**
- A cold `deploy` must come up healthy with **no** manual `migrate`/`collectstatic` (FR-006, SC-003) —
  the Django analogue of Sure's `db:prepare`. `web` waits on ready PG+Redis (no serving against an
  unmigrated/empty DB), applies migrations, and populates `wger-static` so nginx (which starts after
  `web` is healthy) serves a fully styled UI. This is idempotent — a redeploy re-converges and changes
  nothing (SC-003).
- Only `web` migrates; the Celery services rely on the schema `web` prepared, hence they start after
  `web` is healthy. On first boot wger also seeds initial fixtures.

**Alternatives considered.** A separate one-shot migration job (rejected — the image self-migrates; an
extra service is needless). Starting nginx before `web` (rejected — nginx's upstream would be down and
static may not yet be collected).

---

## R5 — Accounts & registration lockdown (fresh instance)

**Decision.** Start **fresh** (no data to import). Keep self-registration **closed**
(`ALLOW_REGISTRATION=False`, `ALLOW_GUEST_USERS=False`) from the start and use wger's **bootstrapped
admin** account created on first boot; change its password immediately. Add household members via the
admin (no open signup).

**Rationale.**
- Unlike Vaultwarden/Actual (Phase 7a, which preserved pre-migration data), there is no prior wger data;
  this is a clean stand-up (FR-003).
- wger **auto-creates a default `admin` account** on first boot against an empty DB (the well-known
  `admin` / `adminadmin` default). Because an admin exists out of the box, we don't need Vaultwarden's
  "open then close" dance — registration can stay **closed from the start** (FR-012, SC-007). The runbook's
  first step is **change the admin password** (the default is a documented weak credential); this is a
  security-critical step, not optional.
- The instance is LAN/VPN-reachable to the whole household, so open self-registration would let anyone
  on the network create accounts — closed is the correct default (spec Edge Case: open-registration
  exposure).

**Alternatives considered.** `ALLOW_REGISTRATION=True` then flip to False (rejected — unnecessary here
since the admin is auto-provisioned; leaving it open even briefly on a LAN-reachable app is avoidable
risk). External SSO/proxy-auth (out of scope).

---

## R6 — Celery jobs: exercise/ingredient DB sync (best-effort)

**Decision.** Run `celery_worker` + `celery_beat` with `USE_CELERY=True` and Redis as broker/backend
(`CELERY_BROKER`/`CELERY_BACKEND` → `redis://cache:6379/<db>`; `DJANGO_CACHE_LOCATION` →
`redis://cache:6379/<other db>`). Leave the scheduled **exercise/ingredient sync** enabled but keep the
heavy **image/video** downloads off/minimal. These jobs are **best-effort** and never gate core logging.

**Rationale.**
- wger's exercise and ingredient databases are synced from the public wger instance by scheduled Celery
  jobs; the API-cache-warming job keeps the exercise API fast. These need **outbound internet** and can
  be slow. Core workout/weight/nutrition logging works **without** them — so a slow/failed/offline sync
  must not block or break logging (spec Edge Case; FR-007, SC-005). Redis backs both the Django cache and
  the Celery broker (distinct logical DB numbers).
- Exercise **image/video** sync is disk-heavy on a 7.5 GB Dell; keep it off or minimal (the exercise
  metadata is what's needed for logging) — a footprint decision, watched via Beszel.
- The **exact `SYNC_*` / `CELERY_*` / `DJANGO_CACHE_*` var names** come verbatim from the pinned image's
  `prod.env` at implementation time.

**Alternatives considered.** `USE_CELERY=False` (rejected — then no exercise DB populates and the app is
a bare logger; the spec wants the exercise library, best-effort). Enabling all image/video sync
(rejected now — disk pressure; revisit if wanted).

---

## R7 — Secrets, exposure, storage & Homepage (cross-cutting)

**Secrets (FR-014).** Only **two** container-referenced secrets, added as placeholders to
`.mise.toml.example` and forwarded to the Periphery env (so a Periphery-run compose resolves `${VAR}`):

| Var | Used by | Generate |
|---|---|---|
| `WGER_SECRET_KEY` | `web` + celery `SECRET_KEY` (Django) | `openssl rand -hex 50` (or Django `get_random_secret_key()`) |
| `WGER_POSTGRES_PASSWORD` | `db` `POSTGRES_PASSWORD` **and** `web`/celery DB password | `openssl rand -hex 32` |

The Postgres password is one secret used in two places (the `db` service's `POSTGRES_PASSWORD` and the
app's DB-connection password) — keep them the same value. **JWT signing keys** are only needed if the
mobile app / PowerSync is enabled (Out of Scope), so none are added now (FR-014). Non-secret config
(`SITE_URL`, `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS`, DB host/name/user, cache/broker URLs, sync flags)
is **inlined as literals** — Komodo does not interpolate `[[VAR]]` into git-pulled compose.

**Exposure (FR-013, SC-008).** One HTTP UI behind the Phase-3 Traefik + wildcard cert at
`wger.ragnaforge.xyz`, which AdGuard resolves to the Dell internally. **No host `ports:`** (Postgres/Redis
stay internal on the `wger` network; the UI is reached only via Traefik→nginx) and **no** router
port-forward. Remote access is via the existing VPN.

**Storage (FR-015, golden rule).** All volumes Dell-local: `wger-static`, `wger-media`, `wger-pgdata`,
`wger-celerybeat`, and optionally `wger-redis`. Nothing on the Mac or `/srv/nfs`. `wger-static` and
`wger-media` are **shared** between `web` (writes) and `nginx` (reads, `:ro`).

**Homepage (FR-011).** Add one tile to the **Apps** group in `stacks/homepage/compose.yaml` — `href`
`https://wger.ragnaforge.xyz`, icon `wger.png` (fallback `mdi-dumbbell` if the brand icon isn't in the
set yet, as Sure did with `mdi-finance`). No native widget (Homepage has no first-class wger summary
widget; the spec asks for a tile).

**Conventions.** One name everywhere (dir = stack = subdomain = Homepage entry): `wger`. Grow the
`docs/CONVENTIONS.md` URL table (`wger.ragnaforge.xyz`) and note the internal-only container ports
(web 8000, nginx 80, Postgres 5432, Redis 6379 — **none published**). Bring-up order, the first-run
admin-password change, and the no-public/static-serving verification go in `docs/runbooks/wger.md`.

---

## Summary of decisions

| # | Decision | Key rationale |
|---|---|---|
| R1 | Six services (web, nginx, celery_worker, celery_beat, db, cache); **trim PowerSync** + optional integrations | Upstream production topology minus the out-of-scope mobile/offline path; lean on a 7.5 GB Dell |
| R2 | Route Traefik → **nginx** (:80); ship nginx.conf **inline** via `configs: content:` (trim `/ps/`) | nginx mandatory for static/media (else unstyled site); Komodo can't bind relative `./config` |
| R3 | Public origin + trusted forwarded headers (`SITE_URL`, `CSRF_TRUSTED_ORIGINS`, `X_FORWARDED_*`) | Traefik terminates TLS; else disallowed-host / CSRF-fail login / wrong asset URLs |
| R4 | `web` self-migrates + collectstatic on boot; `depends_on` healthy db+cache; ordered nginx/celery | Cold deploy healthy, no manual step (Django analogue of Sure's `db:prepare`) |
| R5 | Fresh instance; registration **closed**; use bootstrapped `admin`, change its password first | No prior data; admin auto-provisioned → no open-signup window needed |
| R6 | Celery worker+beat on Redis; exercise/ingredient sync best-effort; image/video sync off/minimal | Exercise library populates without gating core logging; disk-friendly |
| R7 | 2 mise secrets; LAN/VPN-only, no host ports/forward; all volumes on Dell; 1 Homepage tile | Reproducible + never public; golden rule; consistent front door |
