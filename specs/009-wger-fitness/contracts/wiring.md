# Contract: Wiring (intra-stack deps, behind-proxy, exposure)

Like the Phase-7a apps, **wger is standalone — it connects to nothing else in the fleet.** There is
therefore **no cross-app wiring** to reproduce. What this contract pins is: the intra-stack dependency
graph (six services), the behind-proxy contract, the one optional security assert, and the invariants
that keep the app correct and safe (no public exposure, no committed secrets, all state on the Dell).

## Edges

| # | Edge | Type | Reproduced by |
|---|---|---|---|
| 1 | **web → db + cache** | intra-stack dependency | `depends_on: {condition: service_healthy}` + healthchecks |
| 2 | **web → own DB schema + static** | boot-time migrate + collectstatic | `DJANGO_PERFORM_MIGRATIONS=True` + `DJANGO_COLLECTSTATIC_ON_STARTUP=True` |
| 3 | **nginx → web (+ shared static/media)** | reverse proxy + static serving | inline nginx.conf: `proxy_pass http://wger` + `/static`,`/media` aliases on shared `:ro` volumes |
| 4 | **celery_worker/beat → web + cache** | background jobs after schema ready | `depends_on` healthy `web`; Redis broker/backend |
| 5 | **Traefik → nginx** | edge route | canonical Traefik labels on `nginx` (:80); Phase-3 wildcard TLS |
| 6 | **Homepage → wger** | linked tile (no widget) | inline `stacks/homepage/compose.yaml` tile |
| 7 | *(none)* **app → app** | — | wger has no inter-app connection |

## Edge 1, 2 & 4 — start ordering + self-migration

- **Ordering:** `web` declares `depends_on: { db: service_healthy, cache: service_healthy }`; `nginx`
  and `celery_worker` depend on `web` healthy; `celery_beat` depends on `celery_worker` healthy.
  Healthchecks: `db`=`pg_isready -U wger`, `cache`=`redis-cli ping`, `web`=`wget -q -O- http://localhost:8000`
  (upstream), `celery_worker`=`celery -A wger inspect ping`. So the app serves only after PG+Redis are
  ready (FR-006), and nginx starts only once `web` is healthy (static already collected).
- **Self-migration:** `web` runs migrations and `collectstatic` on boot — **no** separate one-shot job,
  **no** manual step. The Celery services rely on the schema `web` prepared. A cold deploy converges to
  healthy and a redeploy changes nothing (idempotent — SC-003).

## Edge 3 — nginx static/media (the wger-specific correctness edge)

- Traefik routes to **nginx:80**, not `web:8000`. nginx `proxy_pass`es `/` to `upstream wger { server
  web:8000; }` and serves `/static/`→`/wger/static/`, `/media/`→`/wger/media/` from volumes **shared**
  with `web` (mounted `:ro` on nginx). `client_max_body_size 100M` for uploads.
- This is spec Edge Case #1 / FR-005 / SC-004: without nginx (or with a broken volume share) the site is
  **served but unstyled** and media 404s. The quickstart explicitly checks a `/static/` and `/media/`
  asset return **200** through nginx.
- The nginx config ships **inline** (`configs: content:`), a **trimmed** upstream copy without the `/ps/`
  PowerSync block (excluded, R1). Editing it needs a container recreate ([[homeserve-inline-configs-need-recreate]]).

## Behind-proxy contract (Edge 5 detail — FR-010, SC-006)

Because Traefik terminates TLS and forwards plain HTTP:

- `SITE_URL` / `ALLOWED_HOSTS` include `wger.ragnaforge.xyz` → no disallowed-host rejection.
- `CSRF_TRUSTED_ORIGINS=https://wger.ragnaforge.xyz` (with scheme) → login/forms don't CSRF-fail.
- `X_FORWARDED_PROTO_HEADER_SET` + `USE_X_FORWARDED_HOST=True` → Django knows the request is HTTPS and
  builds correct `https://` redirect/asset URLs (no redirect loop, no mixed content).
- `AXES_IPWARE_PROXY_COUNT=1` → brute-force lockout keys on the real client IP, not Traefik's.

## Edge 6 — Homepage tile

One linked tile in the **Apps** group → `https://wger.ragnaforge.xyz`. **No native widget** — wger has
no first-class Homepage summary widget usable without extra API wiring, and the spec asks for a tile
(FR-011, SC-006).

## Optional plane-3 assert — wger serving + lockdown (`stacks/wger/configure/setup.yml`)

The one thing worth codifying beyond the quickstart (kept idempotent, GET-only — **never mutates data**):

- Assert `GET https://wger.ragnaforge.xyz/` returns 200 (app up behind the proxy).
- Assert a **static asset** (`GET https://wger.ragnaforge.xyz/static/…`) returns **200** — proves nginx
  is serving static (wger's signature failure mode; FR-005, SC-004). **Fail loudly** if it 404s.
- Assert **self-registration is refused** for an unauthenticated request (FR-012, SC-007).
- Re-runs change nothing. Everything else (logging, persistence, celery, exercise sync) is validated by
  the quickstart rather than a bespoke play — keeping custom code minimal.

## Invariants enforced here

- **No public exposure (FR-013, SC-008):** no host `ports:` on any service (`db`/`cache` stay on the
  internal `wger` network), and **no** router port-forward. Remote access is via the existing VPN only.
- **No committed secrets (FR-014, SC-009):** the 2 container secrets come from `mise`; grep the repo →
  **0** secret values; only `${VAR}` references and `.example` placeholders.
- **Golden rule (FR-015, SC-009):** every volume is Dell-local; **0** state on the Mac or `/srv/nfs`.
- **Idempotency (SC-003):** re-running the assert or redeploying the stack **changes nothing** (boot
  migrate/collectstatic is convergent; no wiring to re-apply).
- **Registration closed (FR-012, SC-007):** the bootstrapped `admin` (password changed on first run) is
  the only privileged account; self-signup is refused.
