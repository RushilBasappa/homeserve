---
description: "Task list — Phase 6: Media & System Stats (Tautulli + Beszel)"
---

# Tasks: Phase 6 — Media & System Stats (Tautulli + Beszel)

**Input**: Design documents from `/specs/007-media-system-stats/`

**Prerequisites**: plan.md, spec.md, research.md (R1–R7), data-model.md, contracts/ (stack-inventory, wiring)

**Tests**: This is an infrastructure/observability phase — validation is **behavioural**
(SC-001…SC-010 in `quickstart.md`), not unit tests. No TDD test tasks are generated; the
Polish phase runs the SC drills.

## Implementation status (2026-07-20)

`/speckit-implement` authored every **codified, reproducible-from-git artifact** (compose
stacks, seed template, plane-3 assertion play, Beszel systems, Komodo declarations, Homepage
tiles + widget, secret placeholders + forwarding, runbook, CONVENTIONS). All authored YAML/TOML
parses cleanly. The remaining tasks are **live deploy + behavioural validation** that require the
running fleet, real credentials (never fabricated), Plex streams, and sleeping the Mac — left for
the operator against the live fleet, exactly as Phase 5's SC drills were handled. `[X]` = done in
repo; `[ ]` = live/operator step (marked ⏳).

Two honest refinements applied during implementation:
- **`[[VAR]]` is not interpolated into git-pulled compose** (per `periphery.compose.yaml`) → node
  IPs / Plex host / agent port are **inlined literals**; only container-consumed secrets
  (`TAUTULLI_API_KEY`, `BESZEL_KEY`) are forwarded to Periphery. `PLEX_TOKEN` and `BESZEL_ADMIN_*`
  are workstation/one-time (not forwarded) — so T003/T005 were scoped accordingly.
- Tautulli's Plex link is a **one-time first-run** (UI wizard or seeded `config.ini`, permitted by
  SC-009); the `configure/setup.yml` play **asserts** it read-only and stays a no-op — rather than
  a fragile static seed that fights Tautulli's config rewrites.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 (Plex watch stats) · US2 (fleet metrics) · US3 (front door)
- Every task names an exact file path or a concrete command target.

## Build order at a glance

1. **Setup** → runbook + secrets/placeholders + Komodo declarations + Homepage prep.
2. **Foundational** → forward secrets to Periphery; confirm Phase-3 edge + Phase-5 Plex are ready.
3. **US1 (P1, MVP)** → Tautulli → prove **now-playing + direct-play/transcode + persistent history** (read-only).
4. **US2 (P1)** → Beszel hub + Dell agent + Mac agent → prove **one fleet view + thresholds + Mac graceful-down**.
5. **US3 (P2)** → Traefik/TLS + Homepage tiles + Tautulli widget → the unified front door.
6. **Polish** → run the SC-001…010 drills, the no-push audit, docs, mark PLAN.md complete.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: repo scaffolding, secret placeholders, and Komodo declarations — everything the
stacks need to exist and be pullable.

- [X] T001 [P] Create the Phase-6 runbook skeleton at `docs/runbooks/phase6-stats.md` (bring-up order, SC-001…010 evidence table stub, Plex-link/threshold/Mac-asleep/no-push drills).
- [X] T002 [P] Add secret placeholders to `.mise.toml.example`: `PLEX_TOKEN` (reused — was only in the live file), `TAUTULLI_API_KEY` (deterministic, `openssl rand -hex 16`), `BESZEL_KEY` (hub public key), `BESZEL_ADMIN_EMAIL`, `BESZEL_ADMIN_PASSWORD` — grouped under a new "Phase 6 — Media & system stats" heading.
- [X] T003 [P] Add non-secret constants to `komodo/variables.toml` if kept out of secrets: Plex internal host/port (`http://plex:32400`), Beszel agent port (45876), and optionally `BESZEL_KEY` as a `[[variable]]` (it is not a secret).
- [X] T004 Declare the four new stacks in `komodo/stacks.toml` (all `webhook_enabled = false`, tags `["phase-6","stats"]`): `tautulli` → `ragnaforge-dell`/`stacks/tautulli/compose.yaml`; `beszel` (hub) → `ragnaforge-dell`/`stacks/beszel/compose.yaml`; `beszel-agent-dell` → `ragnaforge-dell`/`stacks/beszel/agent.compose.yaml`; `beszel-agent-mac` → `ragnaforge-mac`/**same** `stacks/beszel/agent.compose.yaml`. Fix the stray dangling `webhook_enabled = false` from the deleted `media-helpers` stack while here.

**Checkpoint**: runbook exists; placeholders defined; Komodo knows about the four stacks.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: make secrets reachable by the Periphery agents and confirm the upstream deps
(edge + Plex) this phase rides on. **No stack can wire correctly until this is done.**

**⚠️ CRITICAL**: complete before any user-story stack is expected to work.

- [X] T005 Forward the new secrets to the Periphery env: add `PLEX_TOKEN`, `TAUTULLI_API_KEY`, `BESZEL_KEY`, `BESZEL_ADMIN_EMAIL`, `BESZEL_ADMIN_PASSWORD` to `komodo/bootstrap/periphery.compose.yaml` `environment:`, then `make sync-secrets` and recreate the Periphery container (per [[homeserve-ops-access]]).
- [ ] T006 [P] Confirm real values exist in the gitignored `.mise.toml` for every new/reused secret (especially `PLEX_TOKEN` — obtain the Plex **server** token if not already present) and a deterministic `TAUTULLI_API_KEY` is set. ⏳ live/operator
- [ ] T007 [P] Verify prerequisites are live: Phase-3 edge (Traefik + wildcard TLS + AdGuard + Homepage) up, and Phase-5 Plex claimed with at least one title watched (so US1 has data). Record in the runbook. ⏳ live/operator
- [ ] T008 `RunSync` (Komodo) so Core reconciles the four new stacks from `stacks.toml` (or wait ≤5 min for the git poll); confirm they appear as deployable in Komodo. ⏳ live/operator

**Checkpoint**: secrets resolve inside the Periphery env; edge + Plex confirmed; stacks are deployable.

---

## Phase 3: User Story 1 — Plex watch stats (now-playing + transcode + history) (Priority: P1) 🎯 MVP

**Goal**: open one page and see current Plex streams with the **direct-play vs transcode**
indicator, plus persistent per-user history — all **read-only**.

**Independent test**: with a title playing, `tautulli.ragnaforge.xyz` shows the session with
user/title/device/bitrate + play-method; history accumulates and survives a redeploy; zero Plex
writes.

- [X] T009 [US1] Author `stacks/tautulli/compose.yaml` (Dell): image `ghcr.io/tautulli/tautulli:<pinned-tag>`, `container_name: tautulli`, `restart: unless-stopped`, env `PUID/PGID/TZ` (mirror `MEDIA_*` vars), volume `tautulli-config:/config`, `networks: [traefik]` (external), and the canonical Traefik labels routing `tautulli.ragnaforge.xyz` → port **8181**. Declare the `tautulli-config` local named volume. Header comment: golden-rule state, read-only Plex, pinned tag.
- [X] T010 [US1] Seed a reproducible first-run: ship a minimal `config.ini` (PMS host `http://plex:32400`, `PLEX_TOKEN`, PMS identifier, deterministic `TAUTULLI_API_KEY`, `first_run_complete = 1`, bounded history retention per FR-005) so the wizard is skipped — via inline Compose `configs:` or a seeded volume path, whichever survives Tautulli's rewrites (research R4). Reference secrets as `${VAR}`.
- [X] T011 [US1] Author the plane-3 assertion play `stacks/tautulli/configure/setup.yml` (idempotent, `ansible.builtin.uri` against the Tautulli API using `TAUTULLI_API_KEY`): assert the API is reachable, **Plex is connected read-only**, and history is accumulating; **fail loudly** on a stale/broken token (surfacing the "cannot reach Plex" edge case). Include a `# RUN:` header like the Maintainerr play. Fallback path (register Plex via API if seeding failed) in the same play.
- [ ] T012 [US1] Deploy `tautulli` via Komodo (`DeployStack`); run `cd stacks/tautulli/configure && mise exec -- ansible-playbook setup.yml`; confirm it reports Plex connected and is a no-op on re-run. ⏳ live/operator
- [ ] T013 [US1] Validate now-playing + transcode (SC-001): play one **transcoding** and one **direct-play** stream on Plex; confirm both appear at `tautulli.ragnaforge.xyz` with correct user/title/device/bitrate and a **correct play-method label**. ⏳ live/operator
- [ ] T014 [US1] Validate persistence + read-only (SC-002, SC-003): confirm history accumulates; `DestroyStack`+`DeployStack` `tautulli` and confirm **0** history loss; confirm no Plex library/media writes are attributable to Tautulli. ⏳ live/operator

**Checkpoint**: MVP — the audience-and-load signal is live and persistent, read-only. Demoable.

---

## Phase 4: User Story 2 — One fleet view (per-node + per-container + thresholds) (Priority: P1)

**Goal**: open one hub and see **both** the Dell and the Mac — CPU/RAM/disk %/network/temps +
per-container stats + visible threshold breaches — with the Mac degrading gracefully when asleep.

**Independent test**: the hub shows both nodes live + per-container CPU/RAM; a crossed threshold
shows a visible indicator; the Mac shows down/stale when asleep and auto-recovers; history
survives redeploy.

- [X] T015 [US2] Author `stacks/beszel/compose.yaml` (Dell) — **hub ONLY**: service `beszel` (image `henrygd/beszel:<pinned>`, volume `beszel-data:/beszel_data`, `networks: [traefik]`, canonical Traefik labels routing `beszel.ragnaforge.xyz` → port **8090**, one-time admin via `BESZEL_ADMIN_*`). Declare `beszel-data` local named volume. Header: single-purpose hub, golden-rule state, pinned key. (The Dell's agent is the generic stack — T017 — not bundled here.)
- [X] T016 [US2] Author the declarative systems file `stacks/beszel/config.yml` and mount it into the hub via inline Compose `configs:` (Komodo-safe, like Homepage): list the **Dell** system (`${DELL_LAN_IP}` or local, 45876, `BESZEL_KEY`) and the **Mac** system (`${MAC_LAN_IP}`, 45876, `BESZEL_KEY`) so the hub imports both — no manual "Add System" (FR-011). Pin the hub keypair per research R3 so trust survives a volume-wipe rebuild.
- [X] T017 [P] [US2] Author the **generic, node-agnostic** agent `stacks/beszel/agent.compose.yaml`: service `beszel-agent` (image `henrygd/beszel-agent:<pinned>`, `KEY=${BESZEL_KEY}`, `network_mode: host` on port 45876, `docker.sock` RO), **no UI, no volume, no node identity**. Header: one file for every node; adding a node = one `[[stack]]` block + one `config.yml` line, never a new file. Deployed per-node as `beszel-agent-dell` / `beszel-agent-mac` (both Debian Linux — "mac" is the node name).
- [ ] T018 [US2] Deploy `beszel` (hub, Dell) via Komodo; complete one-time admin; then deploy `beszel-agent-dell` (generic agent). Confirm the hub imports systems from `config.yml` and the **Dell** node reports live CPU/RAM/disk %/net/temps + per-container. ⏳ live/operator
- [ ] T019 [US2] Deploy `beszel-agent-mac` (same generic file, `server = ragnaforge-mac`) while the node is awake (Periphery Ok — see [[homeserve-ragnaforge-mac-node]]); confirm the **Mac** node goes green and reports container CPU/RAM. ⏳ live/operator
- [ ] T020 [US2] Configure thresholds in Beszel (e.g. disk > 85%, sustained high CPU/RAM) with **NO notification channel wired** (research R6) — visible indicators only. If threshold config is not captured by `config.yml`, document the one-time setup in the runbook. ⏳ live/operator
- [ ] T021 [US2] Validate one-view + threshold (SC-004, SC-005): confirm both nodes + per-container stats in one view with 0 SSH; cross a threshold and confirm a **visible** breach indicator. ⏳ live/operator
- [ ] T022 [US2] Validate Mac graceful-down + persistence (SC-006, FR-011): sleep/off the Mac → node shows **down/stale**, view intact; wake it → **auto-recovers** with 0 re-registration; redeploy the hub → metric history + systems persist. ⏳ live/operator

**Checkpoint**: the "whether the box can take it" half is live — one fleet view, thresholds visible, Mac best-effort.

---

## Phase 5: User Story 3 — One front door: TLS + Homepage tiles + widget (Priority: P2)

**Goal**: reach both tools at `https://<name>.ragnaforge.xyz` with valid TLS and see them on
Homepage, with a live now-playing summary on the front door.

**Independent test**: both hostnames load over HTTPS (HTTP redirects); both appear as Homepage
tiles; the Tautulli widget shows current stream count without opening the full UI.

- [X] T023 [US3] Confirm/adjust the Traefik labels on `stacks/tautulli/compose.yaml` (T009) and the `beszel` hub (T015) so both resolve at `tautulli.ragnaforge.xyz` / `beszel.ragnaforge.xyz` over HTTPS with the wildcard cert and HTTP→HTTPS redirect (SC-008, FR-012). The Mac agent has **no** router (no UI).
- [X] T024 [US3] Edit `stacks/homepage/compose.yaml` inline configs: add a **Media** tile for Tautulli and an **Infrastructure** tile for Beszel (icons, `href`, description), matching the existing tile style.
- [X] T025 [US3] Add the native **Tautulli widget** to the Homepage service: wire `HOMEPAGE_VAR_TAUTULLI_KEY: ${TAUTULLI_API_KEY}` into the homepage service env (and forward it to Periphery), reference it as `{{HOMEPAGE_VAR_TAUTULLI_KEY}}` in the widget block (url `http://tautulli:8181`), so the front door shows live streams (SC-008). Beszel stays a linked tile (no native widget; optional `customapi` noted for later).
- [ ] T026 [US3] Redeploy `homepage` via Komodo; validate SC-008: both hostnames load over valid TLS, both tiles present, the Tautulli widget shows a live now-playing/stream summary. ⏳ live/operator

**Checkpoint**: both stats surfaces are a glance away from the front door, consistent with every other app.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: prove the whole phase, audit the boundary, document, and sign off.

- [ ] T027 Run the **no-push audit** (SC-007): confirm Beszel has 0 notification channels and Tautulli 0 notification agents — every signal is a dashboard indicator only. Record as the explicit Phase-9 boundary. ⏳ live/operator
- [ ] T028 Run the **idempotent-rebuild** check (SC-009): re-run `stacks/tautulli/configure/setup.yml`, re-import Beszel `config.yml`, redeploy each stack once more — confirm the Plex link + hub↔agent systems reproduce from pinned config with 0 manual UI wiring beyond one-time creds, and nothing changes. ⏳ live/operator
- [ ] T029 [P] Run the **footprint** check (SC-010): read Tautulli + Beszel hub + agents' own steady-state memory from the Beszel per-container view; confirm the combined total stays within the documented budget (a few hundred MB) — the observers are not the load. ⏳ live/operator
- [X] T030 [P] Update `docs/CONVENTIONS.md`: add `tautulli` and `beszel` to the ports/URL tables; note the Mac agent has no routed UI and the containerized-agent host-metric caveat (R2).
- [ ] T031 Fill the SC-001…010 evidence table in `docs/runbooks/phase6-stats.md` from the live runs (T013/T014/T021/T022/T026/T027/T028/T029). ⏳ live/operator
- [ ] T032 Mark **Phase 6 complete** in `PLAN.md` (and cross-link the runbook), mirroring the Phase-5 completion note. ⏳ live/operator

**Checkpoint**: Phase 6 signed off — audience + load are observable, reproducible-from-code, dashboards-only.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T004)**: no deps — do first (mostly parallel).
- **Foundational (T005–T008)**: after Setup. **Blocks all user stories** (secrets must resolve).
- **US1 (T009–T014)**: after Foundational. The **MVP** — independently demoable.
- **US2 (T015–T022)**: after Foundational. **Independent of US1** — can run in parallel with it.
- **US3 (T023–T026)**: after US1 **and** US2 exist (it fronts/links both). Tautulli widget needs US1; Beszel tile needs US2.
- **Polish (T027–T032)**: after US1–US3 are deployed.

### Within a stack

- Author compose (T009/T015/T017) → seed/declare config (T010/T016) → deploy (T012/T018/T019) → wire/assert (T011) → validate (T013–T014 / T021–T022).
- US2: the **hub (T018)** should be up before each **agent** so the imported systems have a hub to report to; the hub compose (T015) and the one generic agent file (T017) can be authored in parallel.

### Parallel opportunities

- **Setup**: T001, T002, T003 are all `[P]` (different files).
- **US1 ∥ US2**: the two P1 stories touch disjoint files (`stacks/tautulli/*` vs `stacks/beszel/*`) and disjoint deploys — a second operator can build Beszel while the first builds Tautulli.
- **T017** (the one generic agent file) is `[P]` against T015/T016 (different file).
- **Polish**: T029, T030 are `[P]`.

## Parallel Example: the two P1 stories

```text
# After Foundational (T005–T008), run in parallel:
Operator A → US1: T009 → T010 → T011 → T012 → T013 → T014   (Tautulli)
Operator B → US2: T015 → T016 → T017 → T018 → T019 → T020 → T021 → T022   (Beszel)
# Then converge on US3 (T023–T026) and Polish (T027–T032).
```

## Implementation Strategy

### MVP first (US1)

1. Setup + Foundational (T001–T008).
2. Tautulli (T009–T012).
3. **STOP and VALIDATE**: now-playing + transcode + persistent history, read-only (SC-001/002/003). Demo the MVP.

### Incremental delivery

1. Add US2 (Beszel fleet view) → the load half (SC-004/005/006).
2. Add US3 (front door) → tiles + widget (SC-008).
3. Polish → no-push audit, idempotency, footprint, docs, sign-off (SC-007/009/010).

## MVP scope

**US1 only** — Tautulli showing live now-playing with the direct-play/transcode breakdown and
persistent per-user history, read-only, at `tautulli.ragnaforge.xyz`. That alone delivers the
single most actionable signal on the 2-core box and is independently valuable without any host
metrics.

## Notes

- **Dashboards only**: no task wires any notification channel — that is Phase 9 (enforced by T027).
- **Golden rule**: only `tautulli-config` and `beszel-data` hold state, both on the Dell; the Mac agent is stateless.
- **Pinned tags**: pin explicit image tags for Tautulli/Beszel/agent (no `:latest`), Diun/Phase-10 intent.
- **Mac deploys need the Mac awake** (Periphery Ok) — T019 in particular; see [[homeserve-ragnaforge-mac-node]].
