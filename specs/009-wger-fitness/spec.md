# Feature Specification: Self-host wger (fitness & workout tracker)

**Feature Branch**: `009-wger-fitness`

**Created**: 2026-07-22

**Status**: Draft

**Input**: User description: "Can you self-host wger. Look at the setup repo" → stand up **wger** (open-source workout/fitness/nutrition manager, AGPLv3) on the lab, following the same house pattern as the rest of the fleet and modelled on the upstream `wger-project/docker` production compose.

## Context

The lab wants a self-hosted **fitness tracker** — wger, an open-source app for logging workouts, tracking body weight/measurements, planning routines, and managing nutrition. It is a personal-data app in the same family as the Phase 7 apps (finance, secrets, media): another day-to-day service the household reaches at `https://<name>.ragnaforge.xyz`, surfaced on Homepage, with all state on the Dell. It is **not** currently in PLAN.md; this feature adds it as an additional app that rides on the platform (edge, DNS, TLS, storage, Komodo) already established in Phases 2–5.

The "setup repo" the user referenced is the upstream **`wger-project/docker`** production Compose. wger is a **Django** application, and unlike the single-container apps in the lab it is inherently a **multi-container** stack — heavier even than Sure (Phase 7a). Modelled on the upstream production topology, it comprises:

1. **web** — the Django/Gunicorn application server (listens on :8000). Runs database migrations and collects static files on boot when configured to (`DJANGO_PERFORM_MIGRATIONS`, `DJANGO_COLLECTSTATIC_ON_STARTUP`), so a cold deploy self-initialises with no manual step.
2. **nginx** — a **mandatory** reverse proxy that serves Django's **static** and **media** files from shared read-only volumes and proxies the rest to `web`. Per upstream: without this service the static files are not served correctly. It listens on :80 and is the service the lab's edge (Traefik) routes to — **not** `web` directly.
3. **celery worker** + **celery beat** — background task queue and scheduler. wger uses these to sync its exercise/ingredient database and cache the exercise API on a schedule; the app is usable without them but the exercise library and periodic jobs depend on them.
4. **db** — **PostgreSQL** (the durable state: accounts, workout logs, weight/nutrition entries).
5. **cache** — **Redis** (Django cache + Celery broker/backend).

Every part follows the house pattern already used by the rest of the fleet: a Compose stack under `stacks/wger/`, Traefik labels routing `https://wger.ragnaforge.xyz` with the existing wildcard TLS (fronting the **nginx** service), a Homepage tile, and config/state on the **Dell** per the golden rule. Deployment is via the existing Komodo/Compose workflow with secrets (Django `SECRET_KEY`, PostgreSQL password, and — only if the mobile app is enabled — JWT signing keys) sourced from `mise` and never committed. Because Traefik terminates TLS in front of it, the Django app must be configured to trust the proxy's `X-Forwarded-*` headers and to accept its public origin for CSRF.

This feature is **stand-up only**. It is a **fresh** instance (there is no pre-migration wger data to preserve, unlike Vaultwarden/Actual); it does **not** add scheduled or offsite backups of its database (that is Phase 10, even though it becomes a backup candidate); it does **not** wire the companion mobile app / offline sync (PowerSync) or email/reCAPTCHA/S3 integrations; and it does **not** expose the app to the public internet — it is reachable on LAN/Tailscale/VPN only, exactly like every other lab UI.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Track workouts & nutrition on a self-hosted wger, data survives redeploy (Priority: P1) 🎯 MVP

As the operator, I open `https://wger.ragnaforge.xyz`, log in, log a workout (and/or a body-weight entry or nutrition item), and find that data still there after I close the browser, come back on another device on the LAN/VPN, and after the stack is redeployed — all over valid TLS.

**Why this priority**: Logging and reliably retaining fitness data is the entire point of the app. A single working, persistent wger instance is a viable MVP that delivers value on its own, independent of any polish (Homepage tile, registration lockdown) or background niceties (exercise-DB sync).

**Independent Test**: Deploy the stack, create/log in as the operator account, record a workout and a body-weight entry, log out and back in from another LAN/VPN device to confirm they're present, then redeploy the stack via Komodo and confirm the account and entries are unchanged.

**Acceptance Scenarios**:

1. **Given** the wger stack is deployed, **When** the operator opens its URL and logs in, **Then** they can create/log a workout, a body-weight entry, and a nutrition item, and those persist across logout/login.
2. **Given** data has been logged, **When** the stack is restarted or redeployed via Komodo, **Then** the account and all logged data are intact (PostgreSQL and uploaded media persisted on the Dell) with **zero** loss.
3. **Given** the app is reached over the network, **When** the operator connects, **Then** it is served over HTTPS with a valid certificate, HTTP is redirected to HTTPS, and it is **not** reachable from the public internet.

---

### User Story 2 - Cold deploy comes up healthy with no manual steps (Priority: P2)

As the operator, I deploy the wger stack from the repository onto a clean host and it comes up **fully working with zero manual intervention**: PostgreSQL and Redis become ready, the Django app applies its migrations and collects static files on boot, nginx serves those static and media files so the UI renders correctly (not an unstyled/broken page), and the Celery worker and beat come up so the exercise database can populate.

**Why this priority**: wger's multi-container topology is its main operational risk — the mandatory nginx/static-file wiring and the DB/cache start-ordering are exactly where a self-host goes wrong (a served-but-unstyled site, a web container serving before migrations, a missing exercise library). Getting a hands-off healthy cold deploy is critical but rides on the same data plane US1 establishes, so it is P2 rather than the MVP.

**Independent Test**: On a clean deploy, confirm (a) `web` becomes healthy only after `db` and `cache` are healthy and migrations have been applied; (b) the served page is fully styled — static and media assets load through nginx (HTTP 200, correct content-type), not 404; (c) the Celery worker and beat report healthy; (d) after the initial exercise sync, the exercise database is populated. No shell-in or manual migrate/collectstatic step is required.

**Acceptance Scenarios**:

1. **Given** a clean deploy, **When** the stack starts, **Then** the Django app becomes reachable only after PostgreSQL and Redis are ready and database migrations have been applied — no serving against an unmigrated/empty database and no crash-loop.
2. **Given** the app is running, **When** the operator loads any page, **Then** static assets (CSS/JS) and media are served correctly through nginx and the page renders fully styled (no broken/unstyled UI, no 404 on static/media).
3. **Given** the Celery worker and beat are part of the stack, **When** the stack is deployed, **Then** both report healthy and the scheduled exercise/ingredient sync populates the exercise database (given outbound internet), without blocking the app's core logging functions if that sync is slow or unavailable.
4. **Given** the stack is redeployed via Komodo, **When** it comes back up, **Then** it returns to a healthy state idempotently with no manual steps and no data loss.

---

### User Story 3 - One front door: wger on Homepage over valid TLS, registration locked down, LAN/VPN-only (Priority: P2)

As the operator, I reach wger the same way as every other service — at `https://wger.ragnaforge.xyz` with valid TLS — I see it as a tile on the **Homepage** dashboard, and new-user self-registration is **closed** after my account exists so nobody on the network can create accounts on my instance, which is reachable only on LAN/Tailscale/VPN.

**Why this priority**: Consistency, discoverability, and closing open registration matter but ride on top of a working app; they are polish once the data plane exists. Because the UI is reachable to everyone on the LAN/VPN, self-registration must be closed so the instance isn't open to account creation by anyone on the network.

**Independent Test**: From a device on LAN/Tailscale, open `https://wger.ragnaforge.xyz`, confirm it loads over valid TLS with HTTP redirected to HTTPS and appears as a tile on Homepage; attempt to self-register a new account and confirm it is refused; confirm the app is not reachable from the public internet.

**Acceptance Scenarios**:

1. **Given** the edge (Traefik + wildcard cert) from Phase 3, **When** the operator opens `wger.ragnaforge.xyz`, **Then** it loads over HTTPS with a valid certificate (Traefik routing to the **nginx** service), HTTP is redirected to HTTPS, and the Django app accepts the request (correct allowed-hosts / CSRF-trusted-origin / forwarded-proto handling behind the proxy).
2. **Given** the Homepage dashboard, **When** the operator opens it, **Then** wger appears as a tile linking to its UI.
3. **Given** the operator account has been created, **When** an unauthenticated visitor attempts to self-register, **Then** registration is refused (self-signup disabled after the operator account is provisioned).
4. **Given** the app is reached over the network, **When** any client connects, **Then** access is limited to LAN/Tailscale/VPN and the app is not router-forwarded or exposed to the public internet.

---

### Edge Cases

- **Missing nginx / static files (the classic wger self-host failure)**: if the mandatory nginx service is dropped or the shared static/media volumes are misconfigured, the site loads but is unstyled/broken and media 404s. The stack MUST keep nginx and serve static/media through it; a bare `web`-only route is a defect.
- **Behind-proxy misconfiguration**: because Traefik terminates TLS, the Django app can otherwise reject requests (disallowed host), produce CSRF failures on login/forms, or build wrong (http/internal) redirect/asset URLs. The app MUST be configured with its public origin (allowed hosts, CSRF-trusted origin) and to trust the proxy's forwarded proto/host headers.
- **Start ordering / cold deploy**: the Django app must not serve or crash-loop before PostgreSQL and Redis are ready and migrations have run; readiness/ordering must be handled so a cold `deploy` comes up healthy without manual `migrate`/`collectstatic`.
- **Exercise-DB sync unavailable or slow**: the scheduled exercise/ingredient/image sync needs outbound internet and can be slow; it MUST NOT block or break core workout/weight/nutrition logging if it is slow, fails, or the box is offline — the exercise library populating is best-effort, core logging is guaranteed.
- **Redeploy / container churn**: redeploying via Komodo must not reset the database, uploaded media, or the operator account; persistence must survive a normal redeploy.
- **Open registration exposure**: because the UI is reachable to everyone on the LAN/VPN, self-registration MUST be closed after the operator account exists so the instance isn't open to arbitrary account creation.
- **Public exposure**: the app MUST NOT be router-forwarded / exposed to the public internet; it is LAN/Tailscale/VPN-only, consistent with the rest of the lab.
- **Secrets in the repo**: the Django `SECRET_KEY`, the PostgreSQL password, and (only if the mobile app is enabled) the JWT signing keys MUST come from `mise` and never be committed; a committed secret is a critical failure.
- **Backups not yet automated**: this is stand-up only. Once it holds real fitness history it becomes a backup candidate, but scheduled/offsite backups and DB dumps are Phase 10; the stand-up-to-Phase-10 gap is a known, documented window.

## Requirements *(mandatory)*

### Functional Requirements

**Core app & data (US1)**

- **FR-001**: The system MUST provide a self-hosted wger instance reachable over the LAN/VPN where the operator can log in and record workouts, routines, body-weight/measurement entries, and nutrition data.
- **FR-002**: All durable application state — the PostgreSQL database (accounts, logs, plans, nutrition) and uploaded **media** — MUST persist on the **Dell** as local named volumes (not on `/srv/nfs`) and MUST survive container restart/redeploy with **zero** data loss.
- **FR-003**: The instance MUST start as a **fresh** instance (no pre-migration wger data exists to import); an operator/admin account MUST be creatable so the app is usable immediately after stand-up.

**Multi-container topology & healthy cold deploy (US2)**

- **FR-004**: The stack MUST run as a multi-container Compose stack modelled on the upstream production topology: the Django **web** app, a **nginx** reverse proxy, a **Celery worker**, a **Celery beat** scheduler, **PostgreSQL**, and **Redis**.
- **FR-005**: A **nginx** service MUST serve Django's **static** and **media** files (from shared volumes) and proxy application requests to `web`; the lab's edge MUST route to **nginx**, not to `web` directly, so the UI renders fully styled with media available. Dropping nginx or bypassing it is not permitted.
- **FR-006**: The Django app MUST apply database **migrations** and make **static files** available on boot automatically (self-initialising cold deploy), and MUST become reachable **only after** PostgreSQL and Redis are ready — no serving against an unmigrated/empty database and no manual migrate/collectstatic step.
- **FR-007**: The **Celery worker** and **beat** services MUST come up healthy so scheduled jobs (exercise/ingredient database sync, exercise-API cache warming) can run; these background jobs MUST NOT block or break core logging if they are slow, fail, or outbound internet is unavailable.
- **FR-008**: PostgreSQL and Redis MUST reach a ready/healthy state before dependents start, and a cold deploy MUST converge to healthy **idempotently** with no manual intervention.

**Edge, proxy correctness, dashboard & lockdown (US3)**

- **FR-009**: The app MUST be reachable at `https://wger.ragnaforge.xyz` with valid TLS via the existing edge (Traefik + wildcard cert), with HTTP redirected to HTTPS, consistent with Phase 3, and MUST use the name `wger` identically across its directory, containers, subdomain, and Homepage entry (one name everywhere).
- **FR-010**: Because Traefik terminates TLS in front of it, the Django app MUST be configured with its public origin — allowed host(s) and CSRF-trusted origin for `wger.ragnaforge.xyz` — and MUST trust the proxy's forwarded protocol/host headers, so login/forms work and generated URLs/redirects use the correct HTTPS public origin (no disallowed-host errors, no CSRF failures, no redirect loops).
- **FR-011**: wger MUST appear on the **Homepage** dashboard as a tile linking to its UI.
- **FR-012**: New-user **self-registration MUST be closed** on the instance after the operator account is provisioned, so arbitrary accounts cannot be created by anyone on the LAN/VPN.

**Security & exposure (cross-cutting)**

- **FR-013**: The app MUST NOT be router-forwarded or exposed to the public internet; access MUST be limited to LAN/Tailscale/VPN, consistent with the rest of the lab's non-VPN services. PostgreSQL and Redis MUST be internal-only (no host ports, not routed).
- **FR-014**: All secrets — the Django `SECRET_KEY`, the PostgreSQL password, and (only if the mobile app is enabled) the JWT signing keys — MUST be sourced from `mise` and MUST NOT be committed to the repository.

**Platform & reproducibility (cross-cutting)**

- **FR-015**: All application state (PostgreSQL data, Redis data if persisted, uploaded media, static files, Celery-beat schedule state) MUST live on the **Dell** as local named volumes and MUST NOT be placed on the shared `/srv/nfs` namespace; per the golden rule it does not run on the Mac.
- **FR-016**: The stack MUST be deployable and reproducible from the repository via the existing **Komodo/Compose** workflow, following the repo conventions (naming, no host `ports:` for HTTP services, Traefik labels on the routed service, inline non-secret config since Komodo does not interpolate repo config), and a redeploy MUST be idempotent.
- **FR-017**: This feature MUST perform **stand-up only**; it MUST NOT introduce scheduled or offsite backups (that is Phase 10), and the stand-up-to-Phase-10 backup gap for this new database MUST be documented rather than left implicit.

### Key Entities *(include if feature involves data)*

- **User account**: the operator's (and any household member's) wger login and profile.
- **Workout / routine log**: recorded training sessions, planned routines, and their entries — the primary durable data.
- **Body-weight & measurement entry**: time-series body metrics tracked by the operator.
- **Nutrition entry / ingredient**: logged nutrition/diet data and the ingredient database it references.
- **Exercise database**: the shared exercise/ingredient library synced from upstream by the Celery jobs (populated content, not operator-authored).
- **Uploaded media**: user-uploaded images/files served by nginx from the media volume on the Dell.
- **App state volumes**: the per-stack local named volumes on the Dell (PostgreSQL data, media, static, Celery-beat state) that must survive redeploys.
- **Secret**: an operator-provisioned credential (`SECRET_KEY`, PostgreSQL password, optional JWT keys) sourced from `mise`, injected at deploy, never committed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The operator can open wger over valid TLS, log in, and record a workout, a body-weight entry, and a nutrition item; all three are still present after logout/login from another LAN/VPN device.
- **SC-002**: A logged entry and the operator account survive a container restart and a Komodo redeploy with **zero** loss (state confirmed on the **Dell**).
- **SC-003**: A **cold deploy from the repo comes up healthy with zero manual steps** — web serves only after PostgreSQL + Redis are ready and migrations have applied, and re-deploying changes nothing (idempotent).
- **SC-004**: On any page load, static assets and media are served through nginx with HTTP 200 and correct content-type — the UI renders fully styled with **0** broken/404 static or media assets.
- **SC-005**: The Celery worker and beat report healthy, and after the initial sync the exercise database is populated; core workout/weight/nutrition logging works even while the sync is running or if it is unavailable.
- **SC-006**: wger is reachable at `https://wger.ragnaforge.xyz` with valid TLS (HTTP→HTTPS) and appears as a tile on the Homepage dashboard; login and form submission succeed with **0** disallowed-host or CSRF errors behind the proxy.
- **SC-007**: Self-registration is **refused** for unauthenticated visitors once the operator account exists.
- **SC-008**: The app is reachable from **0** public-internet paths (no router-forward / public exposure); it is LAN/Tailscale/VPN-only, and PostgreSQL/Redis expose **0** host ports.
- **SC-009**: **0** secrets (`SECRET_KEY`, PostgreSQL password, optional JWT keys) are present in the repository; all are sourced from `mise`, and **0** application state lives on the Mac or `/srv/nfs`.

## Assumptions

- **Tool & topology follow the upstream setup repo**: the app is **wger** (`wger-project`, AGPLv3), deployed modelled on the upstream `wger-project/docker` production Compose — Django **web** + mandatory **nginx** + **Celery worker** + **Celery beat** + **PostgreSQL** + **Redis**. This is a heavier multi-container stack than any current lab app (more services than Sure).
- **Fresh instance, no data to preserve**: unlike Vaultwarden/Actual (Phase 7a), there is no pre-migration wger data; this stands up a clean instance. (If an existing wger export later turns up, importing it is a separate, out-of-scope task.)
- **LAN/VPN-only exposure**: fronted by Traefik at `wger.ragnaforge.xyz`, which resolves internally (AdGuard → the Dell) and is **not** router-forwarded; remote access is via the VPN, never direct public exposure — consistent with the rest of the lab.
- **Storage & golden rule (Phase 4)**: all state (PostgreSQL, media, static, Celery-beat) lives on the **Dell** as local named volumes, never on `/srv/nfs`; the stack does not run on the Mac.
- **Edge & dashboard are ready (Phase 3)**: Traefik + wildcard TLS + AdGuard + Homepage are available to route and surface the app with the standard label + tile pattern; Traefik routes to the **nginx** service (port 80), not the Django app directly.
- **Behind-proxy configuration is required**: because Traefik terminates TLS, the Django app is configured with its public origin (allowed hosts, CSRF-trusted origin) and to trust `X-Forwarded-Proto`/host; the number of trusted proxies matches the single Traefik hop.
- **Reproducibility discipline carries over**: deployment via Komodo/Compose, secrets via `mise`, non-secret config inlined (Komodo does not interpolate repo config), and repo conventions (naming, no host ports for HTTP, Traefik labels on the routed service, one-name-everywhere) established in earlier phases apply unchanged.
- **Background sync needs outbound internet**: the exercise/ingredient/image sync jobs fetch from upstream wger; the box has outbound internet, but these jobs are best-effort and never gate core logging.
- **Single operator / small household**: sized for one operator and possibly a few household members, not a public multi-tenant instance; self-registration is closed after provisioning.
- **Backups are Phase 10**: once it holds real fitness history it is a backup candidate, but scheduled/offsite backups and DB dumps are explicitly Phase 10; this feature only stands the app up.

## Out of Scope

- **Scheduled / offsite backups and DB dumps** of the wger PostgreSQL database — that is **Phase 10 (Backups)**.
- **Companion mobile app / offline sync (PowerSync)** and the JWT signing keys it requires — the web app is the deliverable; mobile/offline sync can be enabled later as a separate change.
- **Optional integrations** — email/SMTP, Google reCAPTCHA, S3/object-storage for media, Prometheus metrics, and reverse-proxy header auth (`AUTH_PROXY_*` / SSO) — all left off; the instance works with none of them.
- **Public-internet exposure / router port-forwarding** — access stays LAN/Tailscale/VPN-only.
- **Importing an existing wger dataset** — this is a fresh instance; migrating a prior export is a separate task if one ever exists.
- **Contributing exercises/ingredients upstream** and running as a public multi-user community instance.
- **Push/alerting on the app's health** — up/down probing and push notifications are Phase 9.
- **Adding wger to PLAN.md as a formal numbered phase** — this feature adds the app following the established app pattern; whether to fold it into the written roadmap is a separate editorial decision.
