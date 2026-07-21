# Feature Specification: Phase 7a — Apps: Finance & Secrets (Actual + Vaultwarden + Sure)

**Feature Branch**: `008-finance-secrets-apps`

**Created**: 2026-07-21

**Status**: Draft

**Input**: User description: "Can you work on phase seven E?" → clarified to **Phase 7a — Apps: finance & secrets** (PLAN.md defines only 7a and 7b).

## Context

With the platform (edge, DNS, TLS, storage, orchestration) and the media stack in place through Phase 6, Phase 7a brings the first **personal-data apps** onto the lab — the ones that hold the household's money and passwords. These are the highest-stakes, most-private workloads in the whole plan, so they are stood up as a distinct phase, ahead of the more casual apps in Phase 7b (photos, home automation).

This phase adds exactly three apps and nothing else:

1. **Vaultwarden — passwords (secrets).** A lightweight, self-hosted, Bitwarden-compatible password server. Single container, config volume on the Dell. The vault is end-to-end encrypted with the user's master password; the server only ever stores encrypted blobs. This is the most safety-critical app in the lab: losing access to it means losing every other password, so preserving any **existing** vault through the migration and getting it back online over valid TLS is the phase's primary objective.

2. **Actual Budget — budgeting (finance).** A fast, self-hosted, local-first budgeting app (envelope budgeting). Single container, config/budget volume on the Dell. If a budget file was preserved from the pre-migration setup (Phase 1), it must come back intact.

3. **Sure — net-worth / wealth tracking (finance).** A community fork of Maybe Finance (AGPLv3). Unlike the other two it is a multi-container Rails app: the web app plus **PostgreSQL** and **Redis**. All of its state lives on the Dell.

**Actual and Sure run side by side on purpose** — they are being trialed together as finance tools; the operator will pick the winner later and retire the other. That side-by-side trial (and the fact that each stack is fully isolated so the loser can be dropped cleanly) is an explicit property of this phase; **choosing** the winner is not part of it.

Every app follows the house pattern already used by the rest of the fleet: a Compose stack under `stacks/<app>/`, Traefik labels routing `https://<app>.ragnaforge.xyz` with the existing wildcard TLS, a Homepage tile, and a config volume on the Dell per the golden rule. Deployment is via the existing Komodo/Compose workflow with secrets sourced from `mise` and never committed.

This phase is **stand-up + one-time data preservation only**. It does not add scheduled or offsite backups of these databases (that is Phase 10, even though these are the prime backup candidates), it does not wire bank/transaction auto-sync, and it does not expose any of these apps to the public internet — they are reachable on LAN/Tailscale/VPN only, exactly like every other lab UI.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Passwords back online, existing vault preserved (Priority: P1) 🎯 MVP

As the operator, I open `https://vaultwarden.ragnaforge.xyz`, unlock with my master password, and find **my existing passwords** — the vault carried over from before the migration — available on every device on the LAN/VPN over valid TLS. New signups are closed so nobody else can register against my server.

**Why this priority**: Passwords are the most critical and most frequently used personal data in the lab; without them the operator is locked out of everything else. Preserving the existing vault (zero credential loss) and restoring daily access is the single most valuable slice — it is a viable MVP even if neither finance app is ever added.

**Independent Test**: Deploy only the Vaultwarden stack, import/restore the preserved vault data volume, open the URL over HTTPS, unlock with the master password, and confirm previously stored logins are present; confirm new-user signup is disabled and the admin surface is gated by a secret token; restart the container and confirm the vault is unchanged.

**Acceptance Scenarios**:

1. **Given** the password server is deployed with any preserved vault data restored to its config volume, **When** the operator opens its URL and unlocks with the master password, **Then** the previously stored logins/items are present with **zero** loss.
2. **Given** the server is running, **When** an unauthenticated visitor attempts to register a new account, **Then** signup is refused (registration disabled after initial account provisioning).
3. **Given** the container is restarted or redeployed via Komodo, **When** it comes back up, **Then** the vault (encrypted store on the Dell) is intact and unlock still works — no reset to an empty vault.
4. **Given** the password server is reached over the network, **When** the operator connects, **Then** it is served over HTTPS with a valid certificate and is **not** reachable from the public internet.

---

### User Story 2 - Budgeting back online, existing budget preserved (Priority: P1)

As the operator, I open `https://actual.ragnaforge.xyz` and find my **budget** — the file preserved from before the migration if one existed — loaded and editable over valid TLS, with its data safely on the Dell so a redeploy never loses a month of budgeting.

**Why this priority**: Budgeting is the other daily-use personal-data app and the second half of "finance & secrets." It is independently valuable and testable without the net-worth tool, and preserving an existing budget (no re-entry of months of transactions) is a hard requirement.

**Independent Test**: Deploy only the budgeting stack, restore any preserved budget data to its volume, open the URL over HTTPS, confirm the existing budget loads (or a fresh budget can be created if none was preserved), edit an entry, restart the container, and confirm the change persisted.

**Acceptance Scenarios**:

1. **Given** the budgeting app is deployed with any preserved budget data restored to its config volume, **When** the operator opens its URL, **Then** the existing budget is available (or a new one can be created cleanly if none existed) over valid TLS.
2. **Given** the operator edits or adds a budget entry, **When** the container is restarted or redeployed, **Then** the change is still present (budget data persisted on the Dell).
3. **Given** the budgeting app is reached over the network, **When** the operator connects, **Then** it is served over HTTPS with a valid certificate and is not reachable from the public internet.

---

### User Story 3 - Net-worth / wealth tracking stood up alongside for the trial (Priority: P2)

As the operator, I open `https://sure.ragnaforge.xyz`, create my account, add a couple of financial accounts, and see a net-worth view — running **alongside** the budgeting app so I can trial both finance tools before committing to one. Its Rails app, PostgreSQL, and Redis all come up healthy and its data survives a redeploy.

**Why this priority**: The wealth-tracking tool completes the finance side and enables the side-by-side trial, but it is a heavier multi-container app and secondary to getting passwords and budgeting back. It rides on the same edge and storage the P1 stories establish, so it can follow them.

**Independent Test**: Deploy the multi-container stack (web + PostgreSQL + Redis), confirm the web app becomes reachable only after its database and cache are ready (migrations applied), create an account and a financial account, open the URL over HTTPS, then redeploy and confirm the account and its data persist.

**Acceptance Scenarios**:

1. **Given** the multi-container stack is deployed, **When** it starts, **Then** the web app becomes reachable only after PostgreSQL and Redis are up and database migrations have been applied (no serving against an unmigrated/empty database).
2. **Given** the app is running, **When** the operator creates an account and adds a financial account, **Then** the net-worth view reflects it and the data is stored in PostgreSQL on the Dell.
3. **Given** the stack is redeployed via Komodo, **When** it comes back up, **Then** the account and its financial data persist with no loss and no re-registration.
4. **Given** the app is reached over the network, **When** the operator connects, **Then** it is served over HTTPS with a valid certificate and is not reachable from the public internet.

---

### User Story 4 - One front door: all three finance & secrets apps on Homepage with valid TLS (Priority: P2)

As the operator, I reach all three apps the same way as every other service — at `https://<name>.ragnaforge.xyz` — and I see them as tiles on the **Homepage** dashboard, so the finance & secrets apps are one click away from the front door and the loser of the Actual-vs-Sure trial can later be removed cleanly without disturbing the others.

**Why this priority**: Consistency and discoverability matter but ride on top of the three working apps; they are polish once the data planes exist. The clean-isolation property (drop the trial loser with one stack removal) is verified here.

**Independent Test**: From a device on LAN/Tailscale, open each of the three hostnames, confirm each loads over valid TLS with HTTP redirected to HTTPS, and confirm all three appear as tiles on the Homepage dashboard; confirm each stack is self-contained (removing one does not affect the others).

**Acceptance Scenarios**:

1. **Given** the edge (Traefik + wildcard cert) from Phase 3, **When** the operator opens each app's hostname, **Then** it loads over HTTPS with a valid certificate and HTTP is redirected to HTTPS.
2. **Given** the Homepage dashboard, **When** the operator opens it, **Then** all three apps appear as tiles linking to their UIs.
3. **Given** the three isolated stacks, **When** one is stopped/removed (e.g. retiring the Actual-vs-Sure trial loser later), **Then** the other apps continue to run unaffected.

---

### Edge Cases

- **Master password loss (Vaultwarden)**: the vault is end-to-end encrypted; if the operator loses the master password the data is unrecoverable by design. This is a documented property of the tool, not a defect of this phase — and it is the reason ongoing backups (Phase 10) matter.
- **Open signup exposure**: because the password/finance UIs are reachable to everyone on the LAN/VPN, Vaultwarden signup MUST be closed after the initial account(s) are created, and its admin surface MUST require a secret token — otherwise anyone on the network could register or reach admin functions.
- **No preserved data to import**: if no pre-migration vault/budget was actually preserved, each app must start cleanly as a fresh instance rather than failing — the import path is best-effort, the fresh-start path is guaranteed.
- **Multi-container start ordering (Sure)**: the Rails web app must not serve (or crash-loop) before PostgreSQL and Redis are ready and migrations have run; readiness/ordering must be handled so a cold `deploy` comes up healthy without manual intervention.
- **Redeploy / container churn**: redeploying any stack via Komodo must not reset a vault, a budget, or the net-worth database; persistence must survive a normal redeploy for all three.
- **Public exposure**: none of these apps may be router-forwarded / exposed to the public internet in this phase; they are LAN/Tailscale/VPN-only, consistent with the rest of the lab. Accidental public exposure of a password server is a critical failure.
- **Trial cleanup**: retiring the losing finance tool later must be a clean single-stack removal (isolated stacks, separate volumes) with no shared state entangling Actual and Sure.
- **Secrets in the repo**: the admin token, database password, and Rails secret key must come from `mise` and never be committed; a committed secret is a critical failure.
- **Backups are not yet automated**: this phase does a **one-time** data preservation/import only. Scheduled and offsite backups of these (prime-candidate) databases are Phase 10; the gap between stand-up and Phase 10 is a known, documented window, not an oversight.

## Requirements *(mandatory)*

### Functional Requirements

**Passwords — Vaultwarden (US1)**

- **FR-001**: The system MUST provide a self-hosted, Bitwarden-compatible password server reachable by the household's existing Bitwarden clients (browser/mobile/desktop) on the LAN/VPN.
- **FR-002**: Any password vault preserved from before the migration MUST be restorable into the app's config volume so the operator's existing logins are present with **zero** loss; if no data was preserved, the app MUST start cleanly as a fresh instance.
- **FR-003**: New-user **signup MUST be disabled** after the initial account(s) are provisioned, and the app's **admin surface MUST be gated by a secret token** sourced from `mise` (never committed).
- **FR-004**: The password server's encrypted data store MUST persist on the **Dell** (local named volume, not `/srv/nfs`) and MUST survive container restart/redeploy without data loss.

**Budgeting — Actual (US2)**

- **FR-005**: The system MUST provide a self-hosted budgeting app reachable over the LAN/VPN, with the operator able to load a preserved budget or create a new one.
- **FR-006**: Any budget data preserved from before the migration MUST be restorable into the app's config volume with **zero** loss; if none was preserved, a fresh budget MUST be creatable cleanly.
- **FR-007**: The budgeting app's data MUST persist on the **Dell** (local named volume, not `/srv/nfs`) and MUST survive container restart/redeploy without data loss.

**Net-worth / wealth tracking — Sure (US3)**

- **FR-008**: The system MUST provide a self-hosted net-worth / wealth-tracking app (the Sure fork of Maybe Finance) reachable over the LAN/VPN, with the operator able to create an account and track financial accounts/balances.
- **FR-009**: The wealth-tracking app MUST run as a multi-container stack comprising the web app plus **PostgreSQL** and **Redis**, all of whose state lives on the **Dell**.
- **FR-010**: The web app MUST become reachable **only after** its PostgreSQL and Redis dependencies are ready and database migrations have been applied — a cold deploy MUST come up healthy without manual steps and MUST NOT serve against an unmigrated database.
- **FR-011**: The wealth-tracking app's PostgreSQL data MUST persist on the **Dell** (local named volume, not `/srv/nfs`) and MUST survive a normal redeploy without loss or re-registration.

**Edge, dashboard & front door (US4)**

- **FR-012**: Every app in this phase MUST be reachable at `https://<name>.ragnaforge.xyz` with valid TLS via the existing edge (Traefik + wildcard cert), with HTTP redirected to HTTPS, consistent with Phase 3, and MUST use the app name identically across its directory, container, subdomain, and Homepage entry (one name everywhere).
- **FR-013**: All three apps MUST appear on the **Homepage** dashboard as tiles linking to their UIs.
- **FR-014**: Each app MUST be a **self-contained, isolated stack** (its own directory, containers, and volumes) so that stopping or removing one — e.g. retiring the Actual-vs-Sure trial loser — does not affect the others.

**Security & exposure (cross-cutting)**

- **FR-015**: None of these apps MUST be router-forwarded or exposed to the public internet; access MUST be limited to LAN/Tailscale/VPN, consistent with the rest of the lab's non-VPN services.
- **FR-016**: All secrets — the password-server admin token, the PostgreSQL password, and the Rails secret key — MUST be sourced from `mise` and MUST NOT be committed to the repository.

**Platform & reproducibility (cross-cutting)**

- **FR-017**: All application state for these apps (the vault store, the budget data, the wealth-tracking PostgreSQL/Redis data) MUST live on the **Dell** as local named volumes and MUST NOT be placed on the shared `/srv/nfs` namespace; per the golden rule none of it runs on the Mac.
- **FR-018**: Each stack MUST be deployable and reproducible from the repository via the existing **Komodo/Compose** workflow, following the repo conventions (naming, no host `ports:` for HTTP services, Traefik labels), and a redeploy MUST be idempotent.
- **FR-019**: This phase MUST perform **one-time** data preservation/import only; it MUST NOT introduce scheduled or offsite backups (that is Phase 10), and the stand-up-to-Phase-10 backup gap MUST be documented rather than left implicit.

### Key Entities *(include if feature involves data)*

- **Password vault**: the end-to-end-encrypted credential store held by Vaultwarden; the server persists only encrypted blobs, the master password never reaches the server.
- **Budget**: the Actual budgeting dataset (accounts, categories, transactions) stored in the app's config volume on the Dell.
- **Financial account / net-worth snapshot**: a Sure-tracked account and its balance over time, aggregated into the net-worth view and stored in PostgreSQL on the Dell.
- **App config volume**: the per-app local named volume on the Dell that holds each app's state and must survive redeploys.
- **Secret**: an operator-provisioned credential (admin token, database password, Rails secret key) sourced from `mise`, injected at deploy, never committed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The operator can open the password server over valid TLS, unlock with the master password, and see the preserved vault with **zero** credential loss (or, if nothing was preserved, a clean empty vault ready to use).
- **SC-002**: New-user signup on the password server is **refused** for unauthenticated visitors, and the admin surface is unreachable without the secret token.
- **SC-003**: The operator can open the budgeting app over valid TLS and load the preserved budget (or create a new one), and an edit survives a container restart with **zero** loss.
- **SC-004**: The wealth-tracking multi-container app comes up **healthy from a cold deploy** with **zero** manual steps (web serves only after PostgreSQL + Redis are ready and migrations applied), and a created account/financial-account survives a redeploy with **zero** loss.
- **SC-005**: **100%** of this phase's apps are reachable at `https://<name>.ragnaforge.xyz` with valid TLS (HTTP→HTTPS) and appear as tiles on the Homepage dashboard.
- **SC-006**: **0** of these apps are reachable from the public internet (no router-forward / public exposure); all are LAN/Tailscale/VPN-only.
- **SC-007**: **0** secrets (admin token, DB password, Rails secret key) are present in the repository; all are sourced from `mise`.
- **SC-008**: On a clean rebuild from the repo via Komodo, all three apps deploy and reach a healthy state, and re-deploying changes nothing (idempotent), with all state confirmed on the **Dell** and **0** state on the Mac or `/srv/nfs`.
- **SC-009**: Removing any one of the three stacks (e.g. retiring the trial loser) leaves the other two running and reachable — the stacks are provably isolated.

## Assumptions

- **Tool selection follows PLAN.md Phase 7a**: secrets = **Vaultwarden**; budgeting = **Actual Budget**; net-worth / wealth tracking = **Sure** (community fork of Maybe Finance, AGPLv3). Vaultwarden and Actual are single-container; Sure requires PostgreSQL + Redis alongside the Rails app.
- **Actual and Sure are trialed side by side on purpose**: both stay running so the operator can compare them; **choosing the winner and retiring the other is a later, out-of-scope decision** — this phase only guarantees the stacks are isolated enough to drop one cleanly.
- **Existing data may exist to preserve**: Phase 1 called for exporting/preserving pre-migration Vaultwarden and Actual config. This phase imports that preserved data if present; if it turns out none was captured, each app starts fresh (the fresh path is the guaranteed one).
- **LAN/VPN-only exposure**: these apps are fronted by Traefik at `*.ragnaforge.xyz`, which resolves internally (AdGuard → the Dell) and is **not** router-forwarded; remote access is via the VPN, never direct public exposure. This is deliberate given the sensitivity of passwords and finances.
- **Storage & golden rule (Phase 4)**: all state (vault store, budget data, Sure's PostgreSQL/Redis) lives on the **Dell** as local named volumes, never on `/srv/nfs`; none of these stacks run on the Mac.
- **Edge & dashboard are ready (Phase 3)**: Traefik + wildcard TLS + AdGuard + Homepage are available to route and surface all three apps using the standard label + tile pattern.
- **Reproducibility discipline carries over**: deployment via Komodo/Compose, secrets via `mise`, and the repo conventions (naming, no host ports for HTTP, Traefik labels, one-name-everywhere) established in earlier phases apply unchanged.
- **Backups are Phase 10**: these are the prime backup candidates, but scheduled/offsite backups (and DB dumps) are explicitly Phase 10; this phase only preserves/imports existing data once.
- **Bank/transaction auto-sync is not wired**: Actual and Sure can integrate with bank-aggregation services, but that requires third-party accounts/credentials and is out of scope here — data entry is manual/CSV import for this phase.
- **Consumers**: primarily the **operator** and household members who use the password vault day-to-day; the finance tools are operator-facing for the trial.

## Out of Scope

- **Scheduled / offsite backups and DB dumps** of these databases (Vaultwarden store, Actual budget, Sure PostgreSQL) — that is **Phase 10 (Backups)**, even though these are the highest-value data in the lab.
- **Choosing the Actual-vs-Sure winner and retiring the loser** — the trial runs both; the decision and cleanup are deferred.
- **The other Phase 7 apps** — Immich (photos), Home Assistant, and n8n are **Phase 7b**, not this phase.
- **Public-internet exposure / router port-forwarding** of any of these apps — access stays LAN/Tailscale/VPN-only.
- **Bank / transaction auto-sync** (SimpleFIN / Plaid / GoCardless and similar) for Actual or Sure — requires third-party credentials/services; manual/CSV import only for now.
- **Single-sign-on / central auth** in front of these apps — each keeps its own authentication, consistent with the rest of the lab.
- **Push/alerting** on these apps' health — up/down probing and push notifications are Phase 9.
