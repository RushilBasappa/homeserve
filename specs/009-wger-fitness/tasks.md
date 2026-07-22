---
description: "Task list — Self-host wger (fitness & workout tracker)"
---

# Tasks: Self-host wger (fitness & workout tracker)

**Input**: Design documents from `/specs/009-wger-fitness/`

**Prerequisites**: plan.md, spec.md, research.md (R1–R7), data-model.md, contracts/ (stack-inventory, wiring)

**Tests**: This is an infrastructure feature — validation is **behavioural** (SC-001…SC-009 in
`quickstart.md`), not unit tests. No TDD test tasks are generated; the Polish phase runs the SC drills.

**Legend**: `[ ]` = to do. **⏳** = live/operator step (needs the running fleet, real credentials — never
fabricated — or a deploy). Everything else is a **codified, reproducible-from-git** artifact authorable
in the repo.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 (log & persist — MVP) · US2 (cold-deploy healthy / nginx static / celery) · US3 (front door + lockdown)
- Every task names an exact file path or a concrete command target.

## Build order at a glance

1. **Setup** → runbook + 2 secret placeholders + Komodo declaration.
2. **Foundational** → forward the 2 container secrets to Periphery; generate real values; confirm the Phase-3 edge.
3. **US1 (P1, MVP)** → author the six-service compose (incl. inline nginx.conf) → **log a workout, it persists across a redeploy over valid TLS**.
4. **US2 (P2)** → **cold deploy comes up healthy with no manual step**; nginx serves static/media; celery + exercise DB.
5. **US3 (P2)** → Homepage tile + valid TLS behind the proxy + **registration closed**, LAN/VPN-only.
6. **Polish** → no-public-exposure + no-committed-secrets audits, idempotent rebuild, docs.

**Key differences from the Phase-7a apps**: wger is **one stack, six services** (not one-compose-per-app),
its **nginx is mandatory** and its config ships **inline** (`configs: content:` — Komodo can't bind
`./config`; editing it later needs a container **recreate**), and it is a **fresh** instance (no
data-restore — instead, change the bootstrapped `admin` password on first run).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: repo scaffolding, secret placeholders, and the Komodo declaration — everything the stack
needs to exist and be pullable.

- [X] T001 [P] Create the runbook skeleton at `docs/runbooks/wger.md` (bring-up order, first-run admin-password change, the inline-nginx-config **recreate** footgun, static-file/no-public verification, SC-001…009 evidence-table stub).
- [X] T002 [P] Add secret placeholders to `.mise.toml.example` under a new "wger (fitness)" heading: `WGER_SECRET_KEY` (`openssl rand -hex 50` — Django `SECRET_KEY`) and `WGER_POSTGRES_PASSWORD` (`openssl rand -hex 32`). Note **no JWT keys** (mobile app / PowerSync is out of scope).
- [X] T003 [P] Declare the stack in `komodo/stacks.toml` (`server = "ragnaforge-dell"`, `webhook_enabled = false`, `tags = ["apps"]`, `repo = "RushilBasappa/homeserve"`): `wger` → `file_paths = ["stacks/wger/compose.yaml"]`. Add a header comment noting it's an added app riding the platform (not a formal PLAN phase).

**Checkpoint**: runbook exists; placeholders defined; Komodo knows about the `wger` stack.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: make the two container secrets reachable by the Dell Periphery agent and confirm the edge
this feature rides on. **The stack cannot resolve `${VAR}` until this is done.**

**⚠️ CRITICAL**: complete before the stack is expected to deploy correctly.

- [X] T004 Forward the two container secrets to the Periphery env: add `WGER_SECRET_KEY` and `WGER_POSTGRES_PASSWORD` to `komodo/bootstrap/periphery.compose.yaml` `environment:` under a "wger (fitness)" comment, then `make sync-secrets` and recreate the Periphery container (per [[homeserve-ops-access]]).
- [ ] T005 [P] Populate real values in the gitignored `.mise.toml`: `WGER_SECRET_KEY` via `openssl rand -hex 50`, `WGER_POSTGRES_PASSWORD` via `openssl rand -hex 32`. ⏳ live/operator
- [ ] T006 [P] Verify the Phase-3 edge is live (Traefik + wildcard TLS + AdGuard + Homepage) and that `wger.ragnaforge.xyz` resolves to the Dell; record in the runbook. ⏳ live/operator
- [ ] T007 `RunSync` (Komodo) so Core reconciles the new `wger` stack from `stacks.toml` (or wait ≤5 min for the git poll); confirm it appears as deployable in Komodo. ⏳ live/operator

**Checkpoint**: secrets resolve inside the Periphery env; edge confirmed; the `wger` stack is deployable.

---

## Phase 3: User Story 1 — Track workouts & nutrition, data survives redeploy (Priority: P1) 🎯 MVP

**Goal**: log a workout / weight / nutrition entry at `https://wger.ragnaforge.xyz` over valid TLS and
have it persist across logout/login and a Komodo redeploy — **0** loss.

**Independent test**: deploy the stack, log in as the operator, record entries, re-open from another
LAN/VPN device, then `DestroyStack`+`DeployStack` and confirm account + entries are intact.

- [X] T008 [US1] Author `stacks/wger/compose.yaml` (Dell) — the **six services**: `web` (`docker.io/wger/server:<pinned release>`, Gunicorn **:8000**, `/start`) + `nginx` (`docker.io/nginx:stable`, **:80**) + `celery_worker` (same wger image, `/start-worker`) + `celery_beat` (same image, `/start-beat`) + `db` (`docker.io/postgres:16`) + `cache` (`docker.io/redis:7-alpine`). Internal network `wger` for all six; **only `nginx`** also on the external `traefik` network. Inline non-secret env (exact keys **verbatim from the pinned image's `config/prod.env`** — the documented set: `SITE_URL=https://wger.ragnaforge.xyz`, `ALLOWED_HOSTS` incl. `wger.ragnaforge.xyz`+localhost, `CSRF_TRUSTED_ORIGINS=https://wger.ragnaforge.xyz`, `X_FORWARDED_PROTO_HEADER_SET`, `USE_X_FORWARDED_HOST=True`, `AXES_IPWARE_PROXY_COUNT=1`, `DJANGO_PERFORM_MIGRATIONS=True`, `DJANGO_COLLECTSTATIC_ON_STARTUP=True`, `DJANGO_DB_ENGINE/HOST=db/PORT=5432/DATABASE=wger/USER=wger`, `DJANGO_CACHE_LOCATION=redis://cache:6379/1`, `USE_CELERY=True`, `CELERY_BROKER/BACKEND=redis://cache:6379/2`, `ALLOW_REGISTRATION=False`, `ALLOW_GUEST_USERS=False`, exercise image/video sync off/minimal). Secrets as `${WGER_SECRET_KEY}` (web+celery `SECRET_KEY`) and `${WGER_POSTGRES_PASSWORD}` (`db` `POSTGRES_PASSWORD` **and** the app DB password — same value); `db` also gets `POSTGRES_DB=wger`/`POSTGRES_USER=wger`. Volumes (Dell-local named): `wger-static:/wger/static` + `wger-media:/wger/media` (mounted **rw on web, ro on nginx** — the shared-static mechanism), `wger-pgdata:/var/lib/postgresql/data`, `wger-celerybeat` (beat schedule), optional `wger-redis:/data`. `depends_on` health: `web`→(`db`,`cache` healthy); `nginx`→`web` healthy; `celery_worker`→`web` healthy; `celery_beat`→`celery_worker` healthy. Healthchecks: `db` `pg_isready -U wger`, `cache` `redis-cli ping`, `web` `wget -q -O- http://localhost:8000`, `celery_worker` `celery -A wger inspect ping`. Canonical Traefik labels on **nginx** → port **80** (router/service name `wger`). **No published host `ports:`** on any service (db/cache internal only). Header comment: golden-rule state, **nginx mandatory** (route to nginx not web), PowerSync excluded, verify image tags + exact env keys at deploy, Diun watches.
- [X] T009 [US1] In the same `stacks/wger/compose.yaml`, add the top-level `configs:` block `wger-nginx` with `content: |` holding a **trimmed** upstream nginx.conf — `upstream wger { server web:8000; }`, `location /static/ { alias /wger/static/; }`, `location /media/ { alias /wger/media/; }`, `location / { proxy_pass http://wger; }` (+ forwarded-header/`Host` proxy_set_headers), `client_max_body_size 100M`, `listen 80;` — **without** the `/ps/` PowerSync block. Wire it into the `nginx` service via `configs: [{source: wger-nginx, target: <nginx conf.d path, e.g. /etc/nginx/conf.d/default.conf>}]` (**verify the exact target against the pinned upstream compose at deploy**). Add a comment: inline because Komodo can't bind `./config`; **editing this block later needs a container recreate** ([[homeserve-inline-configs-need-recreate]]). *(Same file as T008 — sequential, not [P].)*
- [ ] T010 [US1] Deploy `wger` **cold** via Komodo (`DeployStack`); watch the order converge with **0** manual steps: `db`+`cache` healthy → `web` migrates + collects static → `nginx` + `celery_worker` → `celery_beat`. ⏳ live/operator
- [ ] T011 [US1] **First-run security step**: log in as the bootstrapped wger `admin` account and **change its password immediately** (the default `admin`/`adminadmin` is a documented weak credential); record done in the runbook. ⏳ live/operator
- [ ] T012 [US1] Validate log + persistence (SC-001, SC-002): record a **workout**, a **body-weight** entry, and a **nutrition** item; log out and back in from **another** LAN/VPN device → all present; `DestroyStack`+`DeployStack` → account + all three entries intact with **0** loss (`wger-pgdata`/`wger-media`). ⏳ live/operator

**Checkpoint**: MVP — a self-hosted wger logs and persists fitness data over valid TLS. Demoable.

---

## Phase 4: User Story 2 — Cold deploy comes up healthy, no manual steps (Priority: P2)

**Goal**: prove the multi-container topology is correct — a clean deploy self-migrates, nginx serves
static/media (styled UI, no 404), and the Celery worker/beat come up so the exercise DB populates.

**Independent test**: on a clean deploy confirm `web` goes healthy only after `db`+`cache`, a `/static/`
and `/media/` asset return 200 through nginx, the workers report healthy, and the exercise DB populates
after sync — no shell-in / manual `migrate`/`collectstatic`.

- [X] T013 [P] [US2] Author the optional plane-3 assert `stacks/wger/configure/setup.yml` (idempotent, GET-only, `ansible.builtin.uri`; `# RUN:` header like the Vaultwarden/Tautulli plays): assert `GET https://wger.ragnaforge.xyz/` == 200, a **`GET /static/<asset>` == 200** (proves nginx is serving static — **fail loudly** on 404, wger's signature failure mode), and that **self-registration is refused** for an unauthenticated request. Never mutates data; a second run is a no-op.
- [ ] T014 [US2] Validate cold-deploy health + idempotency (SC-003): from a clean deploy confirm all six services reach healthy/running with `web` only healthy after `db`+`cache` and migrations applied (no manual step); `DestroyStack`+`DeployStack` → returns to healthy, nothing changes. ⏳ live/operator
- [ ] T015 [US2] Validate static/media served through nginx (SC-004): the UI renders **fully styled**; `curl -sI https://wger.ragnaforge.xyz/static/<asset>` → **200** (CSS/JS content-type); upload an image in-app, `curl -sI` its `/media/…` URL → **200**. Optionally run `stacks/wger/configure/setup.yml` and confirm the static assert passes and re-run is a no-op. ⏳ live/operator
- [ ] T016 [US2] Validate Celery + exercise DB (SC-005): `celery_worker` healthy (`celery -A wger inspect ping`), `celery_beat` running; after the initial sync the **exercise database** is populated (browse exercises); confirm core logging (SC-001) works **while** the sync runs and if it's unavailable (sync is best-effort, never gates logging). ⏳ live/operator

**Checkpoint**: the six-service stack is provably correct — hands-off cold deploy, styled UI, populated exercise library.

---

## Phase 5: User Story 3 — Front door: Homepage + TLS behind the proxy + registration closed (Priority: P2)

**Goal**: reach wger at `https://wger.ragnaforge.xyz` with valid TLS, see it on Homepage, log in without
proxy/CSRF errors, with self-registration closed — all LAN/VPN-only.

**Independent test**: the hostname loads over HTTPS (HTTP redirects) and appears as a Homepage tile; login
and a form submit succeed with no host/CSRF error; a self-register attempt is refused; the app is not
reachable off the LAN/VPN.

- [X] T017 [US3] Edit `stacks/homepage/compose.yaml` inline configs: add a **wger** tile to the **Apps** group (icon `wger.png`; `mdi-dumbbell` fallback if the brand icon isn't in the set yet, as Sure used `mdi-finance`) with `href: https://wger.ragnaforge.xyz` and a short description, matching the existing tile style. **No native widget.**
- [ ] T018 [US3] Redeploy `homepage` via Komodo; validate TLS + tile + behind-proxy login (SC-006): `curl -sI http://wger.ragnaforge.xyz` redirects to HTTPS with a valid cert; the wger tile appears in the Apps group; log in and submit a form (e.g. add a workout) with **0** "disallowed host" and **0** CSRF errors, links/redirects staying on `https://wger.ragnaforge.xyz`. ⏳ live/operator
- [ ] T019 [US3] Validate registration closed (SC-007): logged out, open the sign-up/register path → **refused** (no self-registration; the bootstrapped `admin` from T011 is the only privileged account). ⏳ live/operator

**Checkpoint**: wger is a glance from the front door, correct behind the proxy, and locked to no-open-signup.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: prove the invariants, document, and sign off.

- [ ] T020 Run the **no-public-exposure audit** (SC-008): confirm no wger service publishes a host `ports:` map (`docker ps` on the Dell), `db`/`cache` are reachable only on the internal `wger` network, and **no** router port-forward targets wger — reachable only on LAN/Tailscale/VPN (verify it does not serve from off-VPN). Record in the runbook. ⏳ live/operator
- [X] T021 [P] Run the **no-committed-secrets audit** (SC-009): `git grep` the repo for the real `WGER_SECRET_KEY` / `WGER_POSTGRES_PASSWORD` values and for `changeme-`; confirm **0** real values in git — only `${VAR}` references and `.mise.toml.example` placeholders.
- [ ] T022 Run the **idempotent-rebuild + placement** check (SC-003, SC-009): on a clean rebuild via Komodo, deploy `wger`, re-run `stacks/wger/configure/setup.yml` (no-op), redeploy once more — confirm it reaches healthy, nothing changes (idempotent), every volume (`wger-static`, `wger-media`, `wger-pgdata`, `wger-celerybeat`, optional `wger-redis`) is on the **Dell**, and **0** state is on the Mac or `/srv/nfs`. ⏳ live/operator
- [X] T023 [P] Update `docs/CONVENTIONS.md`: add `wger.ragnaforge.xyz` to the URL table; note the internal-only container ports (web 8000 / nginx 80 / Postgres 5432 / Redis 6379 — **none published**; the routed port is nginx **80**).
- [ ] T024 Fill the SC-001…009 evidence table in `docs/runbooks/wger.md` from the live runs (T012/T014/T015/T016/T018/T019/T020/T022). ⏳ live/operator
- [X] T025 [P] *(optional, editorial)* Note wger in `PLAN.md`/`README.md` as an added app riding the platform (explicitly **not** a numbered phase — spec Out of Scope) and cross-link `docs/runbooks/wger.md`.

**Checkpoint**: wger signed off — fitness tracker live, reproducible-from-code, LAN/VPN-only, 0 secrets in git.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T003)**: no deps — do first (all `[P]`, different files).
- **Foundational (T004–T007)**: after Setup. **Blocks the stack** (secrets must resolve).
- **US1 (T008–T012)**: after Foundational. The **MVP** — independently demoable. Authors the one compose the whole feature rides on.
- **US2 (T013–T016)**: after US1's compose exists and is deployed (US2 validates the *same* stack's cold-deploy/nginx/celery correctness; T013 adds the assert play in a separate file).
- **US3 (T017–T019)**: after US1 is deployed (routing/lockdown env live in the T008 compose; US3 adds the Homepage tile and validates the front door + registration lockdown).
- **Polish (T020–T025)**: after US1–US3 are deployed.

### Within the stack

- Author compose services/env/volumes/labels (T008) → add inline nginx.conf `configs:` block (T009, same file) → deploy (T010) → change admin password (T011) → validate.
- wger has **no external wiring** — its only dependencies are intra-stack (`web`→healthy `db`/`cache`; `nginx`→`web`; `celery`→`web`/`cache`), handled by Compose `depends_on` + healthchecks (contracts/wiring.md edges 1–5).

### Parallel opportunities

- **Setup**: T001, T002, T003 are all `[P]` (different files).
- **Foundational**: T005, T006 are `[P]`.
- **US2**: T013 (the `configure/setup.yml` assert) is a separate file — authorable `[P]` alongside the US1 compose once the interface (URLs, static path) is known.
- **Polish**: T021, T023, T025 are `[P]`.
- Note: unlike Phase 7a's three-compose split, wger is **one compose file** (T008+T009), so the core authoring is sequential, not parallelizable across services.

## Parallel Example

```text
# Setup — three different files at once:
T001 (runbook)  ∥  T002 (.mise.toml.example)  ∥  T003 (komodo/stacks.toml)

# After Foundational, the compose (T008→T009) and the assert play (T013) can proceed together:
Author stacks/wger/compose.yaml (T008 → T009)   ∥   Author stacks/wger/configure/setup.yml (T013)
# Then deploy (T010) → admin password (T011) → validate US1/US2/US3 → Polish.
```

## Implementation Strategy

### MVP first (US1)

1. Setup + Foundational (T001–T007).
2. Author + deploy the stack, change the admin password (T008–T011).
3. **STOP and VALIDATE**: log a workout/weight/nutrition entry, confirm it survives a redeploy over valid TLS (SC-001/002). Demo the MVP.

### Incremental delivery

1. US1 → a working, persistent wger (MVP).
2. US2 → prove hands-off cold-deploy health, nginx static-serving, and the exercise library (SC-003/004/005).
3. US3 → Homepage tile + behind-proxy TLS + registration closed (SC-006/007).
4. Polish → no-public + no-secrets audits, idempotent rebuild, docs (SC-008/009).

## MVP scope

**US1 only** — a self-hosted wger at `https://wger.ragnaforge.xyz` where the operator logs workouts,
body-weight, and nutrition, and the data survives a redeploy. That single working, persistent instance
is independently valuable even before the cold-deploy hardening (US2) and front-door polish (US3).

## Notes

- **nginx is mandatory**: Traefik routes to the **nginx** service (:80), never `web:8000` directly — else
  the site is served-but-unstyled and media 404s (FR-005, SC-004). The nginx.conf ships **inline**
  (`configs: content:`, T009) because Komodo can't bind a relative `./config`; **editing it later needs a
  container recreate**, not just a redeploy ([[homeserve-inline-configs-need-recreate]]).
- **Cold-deploy self-migrates**: `DJANGO_PERFORM_MIGRATIONS` + `DJANGO_COLLECTSTATIC_ON_STARTUP` on `web`,
  which waits on healthy `db`+`cache` — no manual `migrate`/`collectstatic` (the Sure `db:prepare` analogue).
- **Behind-proxy config is load-bearing**: `SITE_URL`/`ALLOWED_HOSTS`/`CSRF_TRUSTED_ORIGINS`/`X_FORWARDED_*`
  must be set or login CSRF-fails and asset URLs go wrong (FR-010, SC-006).
- **Fresh instance**: no data restore; the first-run step is **changing the bootstrapped `admin` password**
  (T011). Registration stays **closed** from the start (FR-012, SC-007).
- **LAN/VPN-only**: no task publishes a host port or adds a router forward (enforced by T020); `db`/`cache`
  stay internal. Remote access is via the existing VPN.
- **Golden rule**: every volume (`wger-static`, `wger-media`, `wger-pgdata`, `wger-celerybeat`,
  `wger-redis`) is on the **Dell**; nothing on the Mac or `/srv/nfs`.
- **Secrets**: only `WGER_SECRET_KEY`, `WGER_POSTGRES_PASSWORD` are container-referenced (mise → Periphery
  → `${VAR}`); no JWT keys (mobile/PowerSync out of scope).
- **Pinned tags**: pin `wger/server:<release>`, `postgres:16`, `redis:7-alpine`, `nginx:stable` — **verify/
  bump at deploy** and lift the **exact env-var keys from the pinned image's `config/prod.env`**; Diun
  (Phase 10) watches. wger is the **heaviest single stack in the lab** — footprint watched via Beszel.
- **Backups are Phase 10**: this feature stands the app up only; scheduled/offsite backups of `wger-pgdata`
  are out of scope here (the stand-up-to-Phase-10 window is documented in the runbook).
