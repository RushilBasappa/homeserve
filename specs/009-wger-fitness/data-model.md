# Phase 1 — Data Model: wger

wger is an off-the-shelf app; this is not a schema we design but the **entities the stack must persist
and keep correct**, mapped to volumes on the Dell and to the spec's Key Entities. The authoritative
schema is wger's own Django models (migrated on boot, R4); what matters here is *where each thing lives*
and *what invariant protects it*.

## Entities → storage

| Entity (spec) | What it is | Lives in | Volume (Dell) | Survives redeploy? |
|---|---|---|---|---|
| **User account** | operator + household logins/profiles; the bootstrapped `admin` | PostgreSQL | `wger-pgdata` | ✅ (FR-002) |
| **Workout / routine log** | training sessions, routines, log entries — the primary data | PostgreSQL | `wger-pgdata` | ✅ |
| **Body-weight & measurement entry** | time-series body metrics | PostgreSQL | `wger-pgdata` | ✅ |
| **Nutrition entry / ingredient** | logged diet data; references the ingredient DB | PostgreSQL | `wger-pgdata` | ✅ |
| **Exercise database** | shared exercise/ingredient library synced from upstream (Celery, R6) | PostgreSQL (+ cache) | `wger-pgdata` (+ `wger-redis`) | ✅ (re-syncable) |
| **Uploaded media** | user-uploaded images/files, served by nginx | filesystem | `wger-media` (`/wger/media`) | ✅ |
| **Collected static** | Django CSS/JS/images produced by `collectstatic` on boot | filesystem | `wger-static` (`/wger/static`) | ✅ (regenerable) |
| **Celery-beat schedule** | scheduler state for periodic jobs | filesystem | `wger-celerybeat` | ✅ (regenerable) |
| **Secret** | `WGER_SECRET_KEY`, `WGER_POSTGRES_PASSWORD` — from `mise`, injected at deploy | process env only | — (never on disk in repo) | n/a |

**Shared volumes.** `wger-static` and `wger-media` are mounted by **`web`** (read-write — writes static
on boot, receives uploads) **and** `nginx` (read-only — serves them). This share is the mechanism that
makes FR-005/SC-004 work; a broken share = an unstyled site / 404 media.

**Regenerable vs. irreplaceable.** `wger-pgdata` and `wger-media` are the **irreplaceable** state (the
real backup candidates for Phase 10). `wger-static` (rebuilt by `collectstatic`), `wger-celerybeat`
(rebuilt by beat), and the exercise DB / `wger-redis` (re-syncable from upstream, ephemeral cache) are
**regenerable** — losing them costs a rebuild, not user data.

## Relationships & ordering (intra-stack only)

```
                 Traefik (websecure, TLS)           ← Phase-3 edge
                        │  Host(`wger.ragnaforge.xyz`)
                        ▼
                     nginx :80        ── serves /static, /media (ro volumes)
                        │  proxy_pass  /  → web:8000
                        ▼
   web (Django/Gunicorn :8000) ── migrate + collectstatic on boot ──▶ wger-static / wger-media (rw)
        │                     └── reads/writes ──▶ db (PostgreSQL :5432)  [wger-pgdata]
        │                     └── cache/broker ──▶ cache (Redis :6379)
        ├── celery_worker (same image, /start-worker) ── ping health ── exercise sync jobs (outbound)
        └── celery_beat   (same image, /start-beat)   ── schedule ──▶ wger-celerybeat
```

- **Start order (R4):** `db` + `cache` healthy → `web` (migrate/collectstatic) healthy → `nginx` +
  `celery_worker` → `celery_beat`. Enforced by `depends_on: {condition: service_healthy}`.
- **No inter-app edges.** wger talks to nothing else in the fleet (standalone, like the 7a apps).
- **Only `nginx`** is on the external `traefik` network; `web`/`celery_*`/`db`/`cache` are on the
  internal `wger` network. `db`/`cache` publish **no** host ports.

## Validation rules (from requirements)

- **Persistence (FR-002, SC-001/002):** an account + a logged workout/weight/nutrition entry MUST
  survive container restart **and** a Komodo redeploy — verified by writing, redeploying, re-reading.
- **Static/media served (FR-005, SC-004):** every page renders fully styled; a `GET /static/<asset>`
  and `GET /media/<upload>` return **200** via nginx (not 404, not through `web:8000` directly).
- **Cold-deploy self-migration (FR-006, SC-003):** on a clean deploy `web` becomes healthy only after
  `db`+`cache`, with migrations applied and static collected, **no manual step**; redeploy is idempotent.
- **Behind-proxy (FR-010, SC-006):** login and form submission succeed with **0** disallowed-host / CSRF
  errors; generated URLs use the `https://wger.ragnaforge.xyz` origin.
- **Registration closed (FR-012, SC-007):** an unauthenticated self-registration attempt is **refused**.
- **No public exposure (FR-013, SC-008):** **0** host ports published; **0** router forward; reachable
  only via Traefik on LAN/Tailscale/VPN.
- **Golden rule / no committed secrets (FR-014/015, SC-009):** **0** state on Mac or `/srv/nfs`; **0**
  secret values in the repo (only `${VAR}` references + `.example` placeholders).
