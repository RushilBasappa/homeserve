---
description: "Task list — Phase 7a: Apps: Finance & Secrets (Actual + Vaultwarden + Sure)"
---

# Tasks: Phase 7a — Apps: Finance & Secrets (Actual + Vaultwarden + Sure)

**Input**: Design documents from `/specs/008-finance-secrets-apps/`

**Prerequisites**: plan.md, spec.md, research.md (R1–R5), data-model.md, contracts/ (stack-inventory, wiring)

**Tests**: This is an infrastructure phase — validation is **behavioural** (SC-001…SC-009 in
`quickstart.md`), not unit tests. No TDD test tasks are generated; the Polish phase runs the SC drills.

**Legend**: `[ ]` = to do. **⏳** = live/operator step (needs the running fleet, real credentials — never
fabricated — a deploy, or restoring existing personal data). Everything else is a **codified,
reproducible-from-git** artifact authorable in the repo.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 (Vaultwarden/passwords) · US2 (Actual/budgeting) · US3 (Sure/net-worth) · US4 (front door)
- Every task names an exact file path or a concrete command target.

## Build order at a glance

1. **Setup** → runbook + 3 secret placeholders + Komodo declarations.
2. **Foundational** → forward the 2 container secrets (Vaultwarden + Sure) to Periphery; generate real values; confirm Phase-3 edge.
3. **US1 (P1, MVP)** → Vaultwarden → **existing vault preserved, unlock works, signups closed, admin gated**.
4. **US2 (P1)** → Actual → **existing budget preserved, edit survives restart**.
5. **US3 (P2)** → Sure → **4-service stack cold-deploys healthy (self-migrates), net-worth persists**.
6. **US4 (P2)** → TLS + Homepage tiles + **stack isolation** (drop the trial loser cleanly).
7. **Polish** → no-public-exposure + no-committed-secrets audits, idempotent rebuild, docs, mark PLAN.md.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: repo scaffolding, secret placeholders, and Komodo declarations — everything the three
stacks need to exist and be pullable.

- [X] T001 [P] Create the Phase-7a runbook skeleton at `docs/runbooks/phase7a-finance-secrets.md` (bring-up order, one-time data-restore steps for Vaultwarden + Actual, Sure cold-deploy, lockdown + no-public-exposure audits, SC-001…009 evidence-table stub).
- [X] T002 [P] Add secret placeholders to `.mise.toml.example` under a new "Phase 7a — Apps: finance & secrets" heading: `VAULTWARDEN_ADMIN_TOKEN` (Argon2 PHC hash from `vaultwarden hash`; note the `$$`-escaping-in-compose footgun), `SURE_SECRET_KEY_BASE` (`openssl rand -hex 64`), `SURE_POSTGRES_PASSWORD` (`openssl rand -hex 32`). Note that **Actual needs no secret** (login set in-app).
- [X] T003 [P] Declare the three new stacks in `komodo/stacks.toml` (all `server = "ragnaforge-dell"`, `webhook_enabled = false`, tags `["phase-7a","apps"]`): `vaultwarden` → `stacks/vaultwarden/compose.yaml`; `actual` → `stacks/actual/compose.yaml`; `sure` → `stacks/sure/compose.yaml`.

**Checkpoint**: runbook exists; placeholders defined; Komodo knows about the three stacks.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: make the container secrets reachable by the Dell Periphery agent and confirm the edge
this phase rides on. **No stack resolves `${VAR}` until this is done.**

**⚠️ CRITICAL**: complete before any user-story stack is expected to deploy correctly.

- [X] T004 Forward the two container secrets to the Periphery env: add `VAULTWARDEN_ADMIN_TOKEN`, `SURE_SECRET_KEY_BASE`, `SURE_POSTGRES_PASSWORD` to `komodo/bootstrap/periphery.compose.yaml` `environment:` under a "Phase 7a" comment, then `make sync-secrets` and recreate the Periphery container (per [[homeserve-ops-access]]). (Actual contributes none.)
- [ ] T005 [P] Populate real values in the gitignored `.mise.toml`: generate `VAULTWARDEN_ADMIN_TOKEN` via `docker run --rm -it vaultwarden/server /vaultwarden hash` (paste the `$argon2id$…` string verbatim — no `$$` here, only in compose), `SURE_SECRET_KEY_BASE` via `openssl rand -hex 64`, `SURE_POSTGRES_PASSWORD` via `openssl rand -hex 32`. ⏳ live/operator
- [ ] T006 [P] Verify the Phase-3 edge is live (Traefik + wildcard TLS + AdGuard + Homepage) and that `*.ragnaforge.xyz` resolves to the Dell; record in the runbook. ⏳ live/operator
- [ ] T007 `RunSync` (Komodo) so Core reconciles the three new stacks from `stacks.toml` (or wait ≤5 min for the git poll); confirm they appear as deployable in Komodo. ⏳ live/operator

**Checkpoint**: secrets resolve inside the Periphery env; edge confirmed; the three stacks are deployable.

---

## Phase 3: User Story 1 — Passwords, existing vault preserved (Priority: P1) 🎯 MVP

**Goal**: unlock the existing vault at `vaultwarden.ragnaforge.xyz` over valid TLS with **0** credential
loss, with registration closed and the admin panel token-gated.

**Independent test**: restore the preserved `/data` into `vaultwarden-data`, deploy, unlock with the
master password → prior logins present; a stranger cannot register; `/admin` needs the token; a restart
leaves the vault intact.

- [X] T008 [US1] Author `stacks/vaultwarden/compose.yaml` (Dell): image `vaultwarden/server:1.36.0-alpine`, `container_name: vaultwarden`, `restart: unless-stopped`, env `DOMAIN=https://vaultwarden.ragnaforge.xyz` + `SIGNUPS_ALLOWED=false` + `ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}` (**document the `$$`-escaping requirement for the Argon2 hash**), volume `vaultwarden-data:/data`, `networks: [traefik]` (external), canonical Traefik labels routing `vaultwarden.ragnaforge.xyz` → port **80**, and a Docker healthcheck on `/alive`. **Do not publish port 3012** (removed). Declare the `vaultwarden-data` local named volume. Header comment: golden-rule state, E2E-encrypted, LAN/VPN-only, pinned tag (verify at releases URL).
- [X] T009 [P] [US1] Author the optional plane-3 assert `stacks/vaultwarden/configure/setup.yml` (idempotent, GET-only, `ansible.builtin.uri`; `# RUN:` header like the Maintainerr/Tautulli plays): assert `GET /alive` == 200 and that **registration is refused** while `SIGNUPS_ALLOWED=false` (a `POST` register attempt is rejected). **Fail loudly** if signup is unexpectedly open. Never mutates the vault.
- [ ] T010 [US1] **One-time data preservation**: if a pre-migration vault was preserved (Phase 1), **stop** the container, restore `/data` (`db.sqlite3` + `rsa_key.*` + `attachments/`; optionally `sends/` + `config.json`) into `vaultwarden-data`, **delete any stale `db.sqlite3-wal`**, then start — per the runbook. If none was preserved, deploy fresh with `SIGNUPS_ALLOWED=true`, create the account(s), then flip to `false` and redeploy. ⏳ live/operator
- [ ] T011 [US1] Deploy `vaultwarden` via Komodo (`DeployStack`); optionally run `cd stacks/vaultwarden/configure && mise exec -- ansible-playbook setup.yml` and confirm it is a no-op on re-run. ⏳ live/operator
- [ ] T012 [US1] Validate vault preserved + unlock (SC-001): open `vaultwarden.ragnaforge.xyz` over valid TLS, unlock with the master password, confirm prior logins present with **0** loss; `DestroyStack`+`DeployStack` and confirm the vault is unchanged (no reset). ⏳ live/operator
- [ ] T013 [US1] Validate lockdown (SC-002): logged out, a **register** attempt is refused; `/admin` is denied without the Argon2 token and accepted with it. ⏳ live/operator

**Checkpoint**: MVP — passwords are back, preserved, over TLS, with registration locked down. Demoable.

---

## Phase 4: User Story 2 — Budgeting, existing budget preserved (Priority: P1)

**Goal**: load the existing budget at `actual.ragnaforge.xyz` over valid TLS with **0** loss; an edit
survives a redeploy.

**Independent test**: restore `/data` (or import a `.zip`), deploy, confirm the budget loads (or create
one), edit an entry, restart → the edit persists.

- [X] T014 [P] [US2] Author `stacks/actual/compose.yaml` (Dell): image `actualbudget/actual-server:26.7.0-alpine`, `container_name: actual`, `restart: unless-stopped`, volume `actual-data:/data`, `networks: [traefik]` (external), canonical Traefik labels routing `actual.ragnaforge.xyz` → port **5006**, a root-`GET :5006` 200 Docker healthcheck (convention — no official `/health`). **Leave `ACTUAL_HTTPS_*` unset** (plain HTTP behind Traefik). **No secret** — login set in-app. Declare the `actual-data` local named volume. Header comment: golden-rule state, plain-HTTP-behind-proxy, pinned tag (verify at releases URL).
- [ ] T015 [US2] **One-time data preservation**: if a pre-migration budget was preserved, restore the whole `/data` (`server-files/` + `user-files/`) into `actual-data`, **or** import a per-budget `.zip` via *Import → Actual* in the client (encrypted budgets need their password). If none, create a fresh budget in-app. Per the runbook. ⏳ live/operator
- [ ] T016 [US2] Deploy `actual` via Komodo (`DeployStack`); confirm the UI loads and the preserved budget (or a new one) is present. ⏳ live/operator
- [ ] T017 [US2] Validate budget preserved + persistence (SC-003): open `actual.ragnaforge.xyz` over valid TLS, edit/add an entry, `DestroyStack`+`DeployStack`, confirm the budget + edit are fully present — **0** loss. ⏳ live/operator

**Checkpoint**: budgeting is back, preserved, over TLS — the second P1 app is independently live.

---

## Phase 5: User Story 3 — Net-worth (Sure) cold-deploys healthy, data persists (Priority: P2)

**Goal**: the 4-service Sure stack comes up healthy from a **cold** deploy (self-migrates), the operator
tracks net-worth, and the data survives a redeploy.

**Independent test**: cold deploy → `db`+`redis` healthy → `web` runs `db:prepare` and `/up` returns 200,
no manual step; create an account + financial account; redeploy → data persists.

- [X] T018 [P] [US3] Author `stacks/sure/compose.yaml` (Dell) — **four services**: `web` (`ghcr.io/we-promise/sure:stable`, pin `stable@sha256:<digest>` seerr-style, `bin/rails server`, port **3000**) + `worker` (same image, `bundle exec sidekiq`) + `db` (`postgres:16`) + `redis` (`redis:7-alpine`). Internal network `sure` for all four; `web` also on external `traefik`. Env (shared block on web+worker): `SECRET_KEY_BASE=${SURE_SECRET_KEY_BASE}`, `SELF_HOSTED=true`, `RAILS_ASSUME_SSL=true`, `APP_DOMAIN=sure.ragnaforge.xyz`, `DB_HOST=db`/`DB_PORT=5432`/`POSTGRES_DB=sure`/`POSTGRES_USER=sure`/`POSTGRES_PASSWORD=${SURE_POSTGRES_PASSWORD}`, `REDIS_URL=redis://redis:6379/1`, `ONBOARDING_STATE=open` (flip to `closed` post-setup), `dns: [8.8.8.8, 1.1.1.1]`. `db` env: `POSTGRES_*` same. `depends_on: {db: service_healthy, redis: service_healthy}` on web+worker; healthchecks: `db` `pg_isready -U sure`, `redis` `redis-cli ping`, `web` `GET localhost:3000/up`. Volumes: `sure-pgdata:/var/lib/postgresql/data`, `sure-storage:/rails/storage` (web+worker), `sure-redis:/data`. Canonical Traefik labels on `web` → port **3000**. **No published host ports** (db/redis internal only). Header comment: AGPLv3 Maybe fork, self-migrates on boot, heaviest 7a stack, rolling-tag exception.
- [ ] T019 [US3] Deploy `sure` **cold** via Komodo (`DeployStack`); watch `db`+`redis` reach healthy, then `web` self-migrate (`rails db:prepare`) and `/up` return 200 — **0** manual steps. Create the first account; then set `ONBOARDING_STATE=closed` and redeploy. ⏳ live/operator
- [ ] T020 [US3] Validate cold-deploy + persistence (SC-004): add a financial account, confirm the net-worth view reflects it; `DestroyStack`+`DeployStack` `sure` and confirm the account + data persist with **0** loss / **0** re-registration (`sure-pgdata`). ⏳ live/operator

**Checkpoint**: the net-worth trial tool runs alongside Actual; all three apps are live.

---

## Phase 6: User Story 4 — One front door: TLS + Homepage tiles + stack isolation (Priority: P2)

**Goal**: all three at `https://<name>.ragnaforge.xyz` with valid TLS and on Homepage; the three stacks
are provably isolated so the trial loser drops cleanly.

**Independent test**: each hostname loads over HTTPS (HTTP redirects); all three appear as Homepage tiles;
removing one stack leaves the others reachable.

- [X] T021 [US4] Review/confirm the Traefik labels on `stacks/vaultwarden/compose.yaml` (T008), `stacks/actual/compose.yaml` (T014), and `stacks/sure/compose.yaml` — `web` only (T018) so all three resolve at `<app>.ragnaforge.xyz` over HTTPS with the wildcard cert and HTTP→HTTPS redirect (FR-012, SC-005). Sure's `db`/`redis` carry **no** labels.
- [X] T022 [US4] Edit `stacks/homepage/compose.yaml` inline configs: add three tiles to the **Apps** group — Vaultwarden (`vaultwarden.png`), Actual (`actual.png`), Sure (`sure.png`) — each with `href` to `https://<app>.ragnaforge.xyz` and a description, matching the existing tile style. **No widgets** (none has a usable native widget).
- [ ] T023 [US4] Redeploy `homepage` via Komodo; validate SC-005: all three hostnames load over valid TLS, HTTP redirects, and all three tiles appear on the Homepage Apps group. ⏳ live/operator
- [ ] T024 [US4] Validate stack isolation (SC-009): stop/remove **one** stack (simulating retiring the Actual-vs-Sure trial loser, e.g. `sure`) and confirm the other two remain running and reachable over TLS. ⏳ live/operator

**Checkpoint**: all three finance & secrets apps are a glance from the front door and provably isolated.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: prove the sensitive-data invariants, document, and sign off.

- [ ] T025 Run the **no-public-exposure audit** (SC-006): confirm no service publishes a host `ports:` map (`docker ps`), Sure's `db`/`redis` are reachable only on the internal `sure` network, and **no** router port-forward targets any of the three — all reachable only on LAN/Tailscale/VPN. Record in the runbook. ⏳ live/operator
- [X] T026 [P] Run the **no-committed-secrets audit** (SC-007): `git grep` the repo for the three secret values and for `changeme-`; confirm **0** real values in git — only `${VAR}` references and `.mise.toml.example` placeholders (Actual adds none).
- [ ] T027 Run the **idempotent-rebuild + placement** check (SC-008): on a clean rebuild via Komodo, deploy all three, re-run the Vaultwarden assert, redeploy each once more — confirm all reach healthy state, nothing changes (idempotent), every volume is on the **Dell**, and **0** state is on the Mac or `/srv/nfs`. ⏳ live/operator
- [X] T028 [P] Update `docs/CONVENTIONS.md`: add `vaultwarden`, `actual`, `sure` to the URL table; note the internal-only container ports (80 / 5006 / 3000, plus Sure's internal 5432 / 6379 — **none published**).
- [ ] T029 Fill the SC-001…009 evidence table in `docs/runbooks/phase7a-finance-secrets.md` from the live runs (T012/T013/T017/T020/T023/T024/T025/T027). ⏳ live/operator
- [ ] T030 Mark **Phase 7a complete** in `PLAN.md` (and cross-link the runbook), mirroring the Phase-5/6 completion notes. ⏳ live/operator

**Checkpoint**: Phase 7a signed off — passwords + finances live, preserved, reproducible-from-code, LAN/VPN-only.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T003)**: no deps — do first (all `[P]`, different files).
- **Foundational (T004–T007)**: after Setup. **Blocks all user stories** (secrets must resolve).
- **US1 (T008–T013)**: after Foundational. The **MVP** — independently demoable.
- **US2 (T014–T017)**: after Foundational. **Independent of US1**.
- **US3 (T018–T020)**: after Foundational. **Independent of US1/US2**.
- **US4 (T021–T024)**: after the three stacks exist (it fronts/links all of them — T022 tiles need the three; T021 reviews their labels; T024 needs ≥2 deployed).
- **Polish (T025–T030)**: after US1–US4 are deployed.

### Within a stack

- Author compose (T008 / T014 / T018) → [Vaultwarden: author assert T009] → one-time data restore (T010 / T015) → deploy (T011 / T016 / T019) → validate.
- Sure has no external wiring — its only dependency is intra-stack (`web`/`worker` → healthy `db`/`redis`), handled by Compose `depends_on` + healthchecks (contracts/wiring.md edges 1–2).

### Parallel opportunities

- **Setup**: T001, T002, T003 are all `[P]` (different files).
- **US1 ∥ US2 ∥ US3 authoring**: the three compose files touch disjoint paths (`stacks/vaultwarden/*`, `stacks/actual/*`, `stacks/sure/*`) — T008, T014, T018 (and the Vaultwarden assert T009) can be authored in parallel by different operators.
- **Foundational**: T005, T006 are `[P]`.
- **Polish**: T026, T028 are `[P]`.

## Parallel Example: the three app stacks

```text
# After Foundational (T004–T007), author the three stacks in parallel:
Operator A → US1: T008 → T009 → T010 → T011 → T012 → T013   (Vaultwarden — MVP)
Operator B → US2: T014 → T015 → T016 → T017                 (Actual)
Operator C → US3: T018 → T019 → T020                        (Sure)
# Then converge on US4 (T021–T024) and Polish (T025–T030).
```

## Implementation Strategy

### MVP first (US1)

1. Setup + Foundational (T001–T007).
2. Vaultwarden (T008–T011).
3. **STOP and VALIDATE**: existing vault preserved, unlock works, signups closed, admin gated (SC-001/002). Demo the MVP — passwords are the highest-stakes data.

### Incremental delivery

1. Add US2 (Actual) → budgeting preserved (SC-003).
2. Add US3 (Sure) → net-worth trial tool, cold-deploy healthy (SC-004).
3. Add US4 (front door) → TLS + tiles + isolation (SC-005/009).
4. Polish → no-public + no-secrets audits, idempotent rebuild, docs, sign-off (SC-006/007/008).

## MVP scope

**US1 only** — Vaultwarden serving the preserved vault at `vaultwarden.ragnaforge.xyz` over valid TLS,
with registration closed and the admin panel token-gated. Passwords are the most critical, most-used
personal data; restoring daily access with **0** loss is independently valuable even if neither finance
app is ever added.

## Notes

- **LAN/VPN-only**: no task publishes a host port or adds a router forward — a public password/finance
  server is a critical failure (enforced by T025). Remote access is via the existing VPN.
- **Golden rule**: every volume (`vaultwarden-data`, `actual-data`, `sure-pgdata`, `sure-storage`,
  `sure-redis`) is on the **Dell**; nothing on the Mac or `/srv/nfs`.
- **Secrets**: only `VAULTWARDEN_ADMIN_TOKEN`, `SURE_SECRET_KEY_BASE`, `SURE_POSTGRES_PASSWORD` are
  container-referenced (mise → Periphery → `${VAR}`); **Actual has none**. Remember the Vaultwarden
  Argon2 token's `$`→`$$` escaping **in the compose file only**.
- **Pinned tags**: Vaultwarden `1.36.0-alpine`, Actual `26.7.0-alpine` (verify at each releases URL);
  **Sure** publishes only rolling `:stable` — pin `stable@sha256:<digest>` (seerr-style exception),
  Diun/Phase-10 watches.
- **Sure is the heaviest 7a component** and the natural retire-candidate if the Actual-vs-Sure trial
  favours Actual — the isolated stacks (T024/SC-009) make that a clean one-stack removal.
- **Data preservation is one-time** (T010/T015); scheduled/offsite backups are **Phase 10**.
