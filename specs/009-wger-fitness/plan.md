# Implementation Plan: Self-host wger (fitness & workout tracker)

**Branch**: `009-wger-fitness` | **Date**: 2026-07-22 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-wger-fitness/spec.md`

## Summary

Stand up **wger** (open-source workout/fitness/nutrition manager, AGPLv3) as **one isolated stack**
under `stacks/wger/`, following the established house pattern (Compose under `stacks/<app>/`, Traefik
labels → `https://wger.ragnaforge.xyz`, a Homepage tile, Dell-local named volumes, secrets from
`mise`). It is a fresh instance of an off-the-shelf app — no custom application code — modelled on the
upstream **`wger-project/docker`** production compose.

The one thing that makes wger different from every current lab app is its **multi-container Django
topology** (six services, heavier than Sure) with a **mandatory nginx** that serves Django's static &
media files; the lab's edge routes to **nginx**, not to the Django app directly. The design decisions
that carry the spec's risk:

1. **nginx is not optional** (FR-005). Without it the site loads but is unstyled and media 404s (the
   classic wger self-host failure). Traefik's router points at the `nginx` service (:80); nginx serves
   `/static/` and `/media/` from shared volumes and proxies everything else to `web:8000`.
2. **nginx's config ships INLINE** via Compose top-level `configs: content:` (materialised in the
   container), **not** a relative `./config/nginx.conf` bind — because Komodo deploys from a git clone
   where a relative bind doesn't resolve (the same reason homepage/configarr/beszel inline their
   config; [[homeserve-inline-configs-need-recreate]], [[homeserve-beszel]]). Editing that inline
   config later needs a container **recreate**, not just a redeploy.
3. **Self-migrating cold deploy** (FR-006). `DJANGO_PERFORM_MIGRATIONS=True` +
   `DJANGO_COLLECTSTATIC_ON_STARTUP=True` on `web`, which `depends_on` healthy `db` + `cache`, so a
   cold `deploy` migrates and collects static with **no manual step** — the Sure `db:prepare` analogue.
4. **Behind-proxy correctness** (FR-010). Traefik terminates TLS, so the Django app is told its public
   origin (`SITE_URL`, `CSRF_TRUSTED_ORIGINS`, `ALLOWED_HOSTS`) and to trust the forwarded proto/host
   (`X_FORWARDED_PROTO_HEADER_SET`, `USE_X_FORWARDED_HOST`) — otherwise logins CSRF-fail and asset URLs
   go wrong.
5. **LAN/VPN-only, never public** (FR-013): rides the Phase-3 edge; **no host `ports:`** (Postgres/Redis
   stay internal), **no** router forward.
6. **Secrets from `mise`** (FR-014): only two container secrets — `WGER_SECRET_KEY`,
   `WGER_POSTGRES_PASSWORD` — forwarded to the Periphery env and read as `${VAR}`. Everything else is
   inlined as a literal (Komodo does not interpolate `[[VAR]]` into git-pulled compose).

**Excluded by the spec** and therefore trimmed from the upstream topology: the **PowerSync** service
(mobile offline sync — Out of Scope), plus the `/ps/` proxy block in nginx, and all optional
integrations (email/SMTP, reCAPTCHA, S3, Prometheus, proxy-header auth). This keeps the stack to the
six services that make the web app work.

## Technical Context

**Language/Version**: No application code authored. Infrastructure-as-config: a **Docker Compose**
stack under `stacks/wger/`, deployed by **Komodo** (declared in `komodo/stacks.toml`). One optional
idempotent **Ansible** assert co-located at `stacks/wger/configure/` (Phase-5/6 house style). Secrets
via **mise** (`.mise.toml`, gitignored) forwarded to the Periphery env. A new runbook lands at
`docs/runbooks/wger.md`.

**Primary Dependencies** (pin explicit tags where a stable tag exists; **verify/bump at deploy** —
Diun/Phase-10 intent):
- **web / celery_worker / celery_beat**: `docker.io/wger/server:<pinned release, e.g. 2.3>` — the
  Django app (Gunicorn on **:8000**; health `wget http://localhost:8000`). Same image runs the app
  (`/start`), the Celery worker (`/start-worker`), and the Celery beat scheduler (`/start-beat`).
- **nginx**: `docker.io/nginx:stable` — reverse proxy on **:80**; serves `/static/` (alias `/wger/static/`)
  and `/media/` (alias `/wger/media/`), proxies the rest to `web:8000`; `client_max_body_size 100M`.
  The **routed** service.
- **db**: `docker.io/postgres:16` — durable state; health `pg_isready`. (Upstream ships this via
  `services/postgres.yaml`; verify the pinned major at deploy.)
- **cache**: `docker.io/redis:7-alpine` — Django cache **and** Celery broker/backend; health `redis-cli ping`.

**Storage**: All state on **Dell-local named volumes**, never `/srv/nfs` (golden rule; FR-015):
`wger-static` (`/wger/static`, collected static — shared web↔nginx), `wger-media` (`/wger/media`,
uploads — shared web↔nginx), `wger-pgdata` (`/var/lib/postgresql/data`, the DB), `wger-celerybeat`
(Celery-beat schedule state), and optionally `wger-redis` (`/data`). Data survives redeploy (FR-002).

**Testing**: Behavioural validation per `quickstart.md`, mapped to SC-001…SC-009 — log + persist
(SC-001/002), cold-deploy healthy with no manual step (SC-003), static/media served through nginx
(SC-004), celery healthy + exercise DB populates (SC-005), TLS + Homepage + no-CSRF login (SC-006),
registration refused (SC-007), **no public exposure** audit (SC-008), **no committed secrets** +
all-state-on-Dell audit (SC-009).

**Target Platform**: `ragnaforge-dell` (10.0.0.70) — the whole stack and all its state (stateful app →
golden rule). **Nothing on `ragnaforge-mac`**, so the Traefik-can't-route-Mac constraint
([[homeserve-traefik-mac-routing]]) does not arise. Existing Komodo variables `DELL_LAN_IP` /
`FLEET_DOMAIN` cover host/domain; access is LAN/Tailscale/VPN only.

**Project Type**: Infrastructure/documentation monorepo. Changes land in one new `stacks/wger/`
directory plus edits to `komodo/stacks.toml` (+1 `[[stack]]`), `komodo/bootstrap/periphery.compose.yaml`
(+2 forwarded secrets), `stacks/homepage/compose.yaml` (+1 tile), `.mise.toml.example` (+2 placeholders),
`docs/CONVENTIONS.md` (URL/port rows), and a new `docs/runbooks/wger.md`.

**Performance Goals / Footprint**: **The heaviest single stack in the lab** — Django/Gunicorn + nginx +
Celery worker + Celery beat + PostgreSQL + Redis (~roughly 600 MB–1 GB combined) on a 7.5 GB Dell
already carrying the Phase-5/6 media+stats stacks and the Phase-7a apps. This is the plan's real budget
pressure; footprint is observed via the Phase-6 Beszel fleet view, and the exercise-image/video sync is
left off/minimal to avoid disk growth. See Complexity Tracking.

**Constraints**:
- **nginx mandatory** — edge routes to nginx (:80), which serves static/media; a `web`-only route is a defect (FR-005, SC-004).
- **Config inline, not bind** — nginx.conf via `configs: content:` (Komodo-safe); editing it needs a recreate (FR-016).
- **Cold-deploy self-migrates** — `DJANGO_PERFORM_MIGRATIONS`/`DJANGO_COLLECTSTATIC_ON_STARTUP` + `depends_on` health; no manual migrate/collectstatic (FR-006, SC-003).
- **Behind-proxy config** — public origin + trusted forwarded headers so login/CSRF/asset URLs are correct (FR-010, SC-006).
- **LAN/VPN-only, never public** — no router forward, no host ports; PG/Redis internal-only (FR-013, SC-008).
- **Secrets from `mise`** — 2 container secrets forwarded; everything else inlined (FR-014, SC-009).
- **Golden rule** — every volume on the Dell; nothing on the Mac or `/srv/nfs` (FR-015).
- **Stand-up only** — scheduled/offsite backups are Phase 10 (FR-017).

**Scale/Scope**: One household, one node (Dell), one new UI, **six new containers** in one stack. No
inter-app wiring — wger is standalone (like the 7a apps); the only intra-stack coupling is
web→db/cache, nginx→web, and celery→web/cache.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution (`.specify/memory/constitution.md`) is an **unfilled template** — no ratified
principles, so there are no formal gates. The project's *de facto* principles from `PLAN.md` /
`CONVENTIONS.md` are upheld:

- **Stateful → Dell**: the whole stack and every volume are Dell-local; nothing on the Mac or `/srv/nfs`. ✅
- **Off-the-shelf, minimal custom code**: wger runs from its own maintained images; the only authored
  artifacts are one Compose file (with an inline nginx.conf), config/doc edits, and an optional thin
  idempotent assert play. No application code. ✅
- **Reproducible from git**: one stack in `stacks/`, declared in `komodo/stacks.toml`; secrets in `mise`;
  a clean rebuild reproduces the app (subject to the wger image-tag verify caveat below). ✅
- **No secrets in the repo**: the 2 new secrets are placeholders in `.mise.toml.example`, referenced as
  `${VAR}`; non-secret config is inlined. ✅
- **LAN/VPN-only edge**: no router-forward, no published host ports; the same Phase-3 Traefik +
  wildcard-TLS front door, nothing public. ✅
- **Isolated stack**: its own directory/containers/volumes/network — self-contained, removable in one
  stack delete. ✅

**Result: PASS.** No unjustified complexity. Three honest, bounded caveats are recorded in Complexity
Tracking (six-service footprint; inline-nginx-config recreate; wger image-tag pinning).

*Post-Phase-1 re-check: still PASS — the design added no new principle-relevant surface; nginx stays
the sole routed service, PG/Redis stay internal, all state stays on Dell, secret count stays at two.*

## Project Structure

### Documentation (this feature)

```text
specs/009-wger-fitness/
├── plan.md              # This file
├── research.md          # Phase 0 — images, ports, env, nginx-inline, self-migrate, lockdown, exclusions
├── data-model.md        # Phase 1 — entities (account, workout log, weight/nutrition, exercise DB, media, volumes, secret)
├── quickstart.md        # Phase 1 — validation runbook (SC-001…SC-009)
├── contracts/
│   ├── stack-inventory.md    # stack × node × services × ports × volumes × secrets × inline-config
│   └── wiring.md             # intra-stack deps (web→db/cache, nginx→web, celery→web), behind-proxy contract, no-public invariant
├── checklists/
│   └── requirements.md       # Spec quality checklist (from /speckit-specify) — all pass
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
stacks/
└── wger/
    ├── compose.yaml            # Dell — web + nginx + celery_worker + celery_beat + db(postgres) + cache(redis);
    │                           #   inline configs: nginx.conf; Traefik labels on NGINX (port 80);
    │                           #   wger-static/wger-media/wger-pgdata/wger-celerybeat[/wger-redis]
    └── configure/
        └── setup.yml           #   PLANE 3 (optional, idempotent) — assert a /static asset is 200 (nginx serving)
                                #   + registration refused; GET-only, never mutates data

komodo/
└── stacks.toml                 # EDIT — +1 [[stack]] wger, server=ragnaforge-dell, webhook_enabled=false, tags=["apps"]

komodo/bootstrap/
└── periphery.compose.yaml      # EDIT — forward the 2 container secrets (WGER_SECRET_KEY, WGER_POSTGRES_PASSWORD)

stacks/homepage/compose.yaml    # EDIT — add a wger tile to the Apps group (icon wger.png; mdi-dumbbell fallback)

docs/
├── CONVENTIONS.md              # EDIT — grow the URL/port table (wger.ragnaforge.xyz; internal 8000/80/5432/6379)
└── runbooks/
    └── wger.md                 # NEW — bring-up order, first-run admin password change, lockdown, static-file verify, no-public audit

.mise.toml.example              # EDIT — +2 placeholders (WGER_SECRET_KEY, WGER_POSTGRES_PASSWORD)
```

**Structure Decision**: **One stack, six services** (`stacks/wger/compose.yaml`) — `web` + `nginx` +
`celery_worker` + `celery_beat` on an internal `wger` network, with **only `nginx`** also on the shared
external `traefik` network for its route; `db` (`postgres:16`) + `cache` (`redis:7-alpine`) on the
internal `wger` network only (never exposed). This mirrors the Phase-5 `arr` stack and Phase-7a `sure`
stack's "multi-service unit as one deployable" pattern, extended by wger's mandatory static-serving
`nginx`. The nginx config is shipped **inline** (`configs: content:`) rather than as a host bind, per
the Komodo-safe house pattern. A `configure/setup.yml` assert is included only for the one thing worth
codifying — that static assets are actually served (wger's signature failure mode) and registration is
closed — keeping custom code minimal; everything else is validated by the quickstart.

## Complexity Tracking

| Caveat (not a violation) | Why it exists | How it is bounded |
|---|---|---|
| **Six-service stack — the heaviest in the lab** | wger is a Django app that inherently needs a static-serving nginx, a Celery worker **and** beat, PostgreSQL, and Redis; ~600 MB–1 GB combined on a 7.5 GB Dell already running Phases 5/6/7a. | This is the app's real architecture, not accidental complexity. **PowerSync and all optional integrations are excluded** (spec Out of Scope), trimming it to the minimum working web stack. Footprint watched via the Phase-6 Beszel view; if RAM-pressured, wger is deployed after the 7a apps and can be stopped without touching them (isolated stack). |
| **nginx.conf must ship inline (`configs: content:`), not as `./config` bind** | Komodo deploys from a git clone / Periphery container where a relative `./config/nginx.conf` bind resolves to a path the daemon can't find → an empty mount ([[homeserve-beszel]], [[homeserve-inline-configs-need-recreate]]). | Use the established inline-`configs:` pattern (homepage/configarr/traefik). Documented trade-off: **editing** the inline nginx.conf later requires a container **recreate** (DestroyStack+DeployStack), not just a redeploy — noted in the stack header and runbook. |
| **wger/server ships version + `latest` tags; DB image via upstream include** | The upstream compose uses `wger/server:latest` and pulls Postgres via `services/postgres.yaml`; there is no long-term-frozen tag guarantee. | Pin an explicit `wger/server:<release>` and `postgres:16` / `redis:7-alpine` in the compose; **verify/bump the exact tags at deploy** and let **Diun** (Phase 10) surface updates — same verify-at-deploy discipline as every other stack header. |
