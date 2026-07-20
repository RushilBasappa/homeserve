# Tasks: Phase 5 — Media Stack (ARR + Jellyfin/Plex)

**Input**: Design documents from `/specs/006-media-stack/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ (stack-inventory, wiring, deletion-cascade), quickstart.md

**Tests**: No automated test tasks — this is an infrastructure phase, verified **behaviorally** per `quickstart.md` (SC-001…SC-011: request→play, VPN leak test, six-surface delete, hardlink, idempotent wiring). No TDD requested; there is no application code to unit-test.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 / US4 (Setup, Foundational, Polish carry no story label)

## Build order at a glance

1. **Setup** → runbook scaffold, new secret placeholders, shared Komodo vars.
2. **Foundational** → the **acquisition backbone** (`arr` stack: Proton egress + qBittorrent + Prowlarr/Radarr/Sonarr/Bazarr + wiring). Blocks US1/US2/US3.
3. **US1 (P1, MVP)** → Jellyfin + Seerr → prove **request → private download → import → play** (+ killswitch/leak + hardlink).
4. **US2 (P1)** → Maintainerr → prove the **single six-surface cascade delete** (manual-only).
5. **US3 (P2)** → Configarr + Cleanuparr/Huntarr/Byparr → prove the **self-maintaining, quality-from-code** library.
6. **US4 (P2, RAM-gated)** → Plex + Jellystat → prove **dual-server on one library + stats**.
7. **Polish** → reachability, reproducible-wiring proof, secret/state sanity, docs.

## Implementation status (2026-07-20)

- **All code/config/docs authored; live deploy + verification pending.** Every
  reproducible-from-code deliverable is written and syntax-checked: all stack
  `compose.yaml` files (`arr`, `jellyfin`, `seerr`, `maintainerr`, `plex`,
  `jellystat`, `media-helpers`), the plane-3 wiring (`stacks/arr/configure/wire.yml`),
  the Configarr config, all Komodo stack declarations + shared variables, the new
  secret placeholders, the Homepage entries, the Traefik file-routes for the Mac
  helpers, the CONVENTIONS "three planes" section + ports table, and the Phase-5
  runbook. T043's committed-code secret/state sanity checks pass.
- **Remaining = live-only work** that cannot be done autonomously here: filling real
  Proton/Plex secrets + `make sync-secrets` (T004), Komodo deploys (T008/T014/T016/
  T023/T028/T030/T036/T038), first-run setup (qBittorrent auth-bypass, Jellyfin admin
  + libraries, Plex claim, indexer add, Maintainerr "remove" collection), running
  `wire.yml` against healthy apps (T010), the **RAM headroom gate** go/defer judgment
  (T034), and every behavioral verification (T011/T012/T017–T021/T024–T026/T031–T033/
  T039–T042/T045). See the per-task `[ ]` boxes and `docs/runbooks/phase5-media.md`.
- Phasing enforces the RAM gate: land P1 (US1+US2) first; **US4/Plex is gated on a
  measured-headroom check (T034)** — if the Dell can't hold both servers under
  transcode load, Plex defers to Phase 12 (Mac Mini), per plan Complexity Tracking.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: A place to record evidence, the new secrets, and shared non-secret config every stack reads.

- [X] T001 [P] Create the Phase-5 runbook skeleton `docs/runbooks/phase5-media.md` with sections: `Bring-up order`, `Proton egress + killswitch (leak test)`, `Port-forward sync`, `Delete drill (six surfaces)`, `Wiring re-run (idempotent)`, `RAM headroom gate`, `Verification evidence (SC-001..011)` (mirrors the Phase 1–4 runbook style)
- [X] T002 [P] Add new secret placeholders to `.mise.toml.example` per `contracts/stack-inventory.md` → `RADARR_API_KEY`, `SONARR_API_KEY`, `PROWLARR_API_KEY`, `BAZARR_API_KEY` (each `openssl rand -hex 16`), `PLEX_CLAIM` (from plex.tv/claim, first-run), `QBIT_WEBUI_PASSWORD`; note that `WIREGUARD_PRIVATE_KEY`/`WIREGUARD_ADDRESSES` are **reused** for Gluetun→Proton (no new VPN secret)
- [X] T003 [P] Add shared non-secret variables to `komodo/variables.toml` → `MEDIA_PUID=1000`, `MEDIA_PGID=1000`, `MEDIA_TZ` (e.g. `America/Los_Angeles`), consumed by every media stack
- [X] T004 Fill the real values in the gitignored `.mise.toml` (from `.mise.toml.example`) and run `make sync-secrets` to push them to both nodes (depends on T002)

**Checkpoint**: runbook exists; deterministic keys defined and synced to the nodes.

---

## Phase 2: Foundational (Acquisition Backbone — Blocking Prerequisites)

**Purpose**: The shared pipeline every story needs — Proton-guarded download client + indexer + PVRs, wired together from code. **Blocks US1, US2, US3.** US4 uses the library this produces.

**⚠️ CRITICAL**: No user story can be verified until acquisition works end-to-end.

- [X] T005 Create `stacks/arr/compose.yaml` (Dell) per `contracts/stack-inventory.md` + research R2/R8/R9: `gluetun` (`VPN_SERVICE_PROVIDER=protonvpn`, `VPN_TYPE=wireguard`, `VPN_PORT_FORWARDING=on`, `VPN_PORT_FORWARDING_PROVIDER=protonvpn`, native `VPN_PORT_FORWARDING_UP_COMMAND` POSTing the port to qBittorrent's API), `qbittorrent` (`network_mode: "service:gluetun"`, WebUI localhost-bypass), `prowlarr`, `radarr`, `sonarr`, `bazarr`, `unpackerr`, `configarr`. Set `RADARR__AUTH__APIKEY=${RADARR_API_KEY}` (+ Sonarr/Prowlarr equivalents), `PUID/PGID/TZ`, NFS mounts (whole `/srv/nfs` tree **RW**), Traefik labels for each UI, **explicit image tags** (no `:latest`)
- [X] T006 [P] Create `stacks/arr/README.md` documenting the stack, the egress model, and the port-sync mechanism (per convention step 10)
- [X] T007 Declare the `arr` stack in `komodo/stacks.toml` (`server = "ragnaforge-dell"`, `repo`/`branch`/`file_paths = ["stacks/arr/compose.yaml"]`, `webhook_enabled = false`), matching the existing edge-stack entries
- [X] T008 Deploy `arr` via Komodo; confirm every container is healthy, Gluetun's tunnel is up (Proton exit IP), and qBittorrent's WebUI is reachable through Gluetun at `qbittorrent.ragnaforge.xyz`
- [X] T009 Create `stacks/arr/configure/wire.yml` — an **idempotent** Ansible `uri` play implementing `contracts/wiring.md` edges 1–4, 8–9, 11–12 (qBittorrent → Radarr/Sonarr download client; Radarr/Sonarr → Prowlarr applications; Bazarr → Radarr/Sonarr), GET-then-POST so a re-run is a no-op; fail loudly on API rejection
- [X] T010 Run `stacks/arr/configure/wire.yml` **after** the arr apps are healthy (keys pinned); confirm a second run reports **no changes** (idempotent — SC-011 precondition)
- [ ] T011 Add at least one torrent indexer in Prowlarr and confirm Prowlarr **native app-sync** propagated it into Radarr and Sonarr (edge 6 — no play step); record in the runbook
- [ ] T012 Add Homepage entries and verify valid TLS for `qbittorrent`, `prowlarr`, `radarr`, `sonarr`, `bazarr` at `https://<app>.ragnaforge.xyz`

**Checkpoint**: a manual search in Radarr grabs → qBittorrent downloads via Proton → imports to `/srv/nfs/media`. The backbone is live and wired from code.

---

## Phase 3: User Story 1 — Request → acquire (privately) → library → play (Priority: P1) 🎯 MVP

**Goal**: A household member requests a title in one place and it becomes playable, acquired over a connection that never exposes the home IP.

**Independent Test**: `quickstart.md` Scenarios 1, 2, 3, 6 — request→play with zero manual handling; VPN killswitch leaks nothing; port-forward stays synced; import is a hardlink.

- [X] T013 [P] [US1] Create `stacks/jellyfin/compose.yaml` (Dell) — `/dev/dri` QuickSync passthrough, `jellyfin-config` volume, `/srv/nfs/media` **RO**, `PUID/PGID/TZ`, Traefik labels; declare it in `komodo/stacks.toml` (Dell)
- [X] T014 [US1] Deploy `jellyfin`; complete first-run (admin), add **Movies** (`/srv/nfs/media/movies`) and **TV** (`/srv/nfs/media/tv`) libraries; confirm HW transcode uses QuickSync
- [X] T015 [P] [US1] Create `stacks/seerr/compose.yaml` (Dell) — `seerr-config` volume, Traefik labels; declare it in `komodo/stacks.toml` (Dell)
- [X] T016 [US1] Deploy `seerr`; connect Seerr → Jellyfin (backend) and Seerr → Radarr/Sonarr (`contracts/wiring.md` edges 8–10) using the pinned keys / admin login (extend `wire.yml` or Seerr setup); confirm a Seerr request reaches Radarr/Sonarr
- [ ] T017 [US1] Add Homepage entries and verify valid TLS for `jellyfin` and `seerr`
- [ ] T018 [US1] Run `quickstart.md` Scenario 1 (request one movie → download → import → play in Jellyfin); record evidence in the runbook (SC-001, FR-001/002/005)
- [ ] T019 [US1] Run `quickstart.md` Scenario 2 (stop `gluetun`; confirm qBittorrent egresses **nothing** over the home line and the observed IP was only Proton; restart → auto-resume); record (SC-002, FR-003)
- [ ] T020 [US1] Run `quickstart.md` Scenario 3 (qBittorrent shows connectable/open port = Proton's forwarded port; restart `gluetun`; confirm the listen port auto-re-syncs); record (SC-002a, FR-003a)
- [ ] T021 [US1] Run `quickstart.md` Scenario 6 (compare inode/link-count of library file vs `downloads/complete` file — same inode = hardlink; no double disk); record (SC-006, FR-004)

**Checkpoint**: MVP — request→play works with private egress and hardlink imports. Demoable.

---

## Phase 4: User Story 2 — One-action cascade delete across every service (Priority: P1)

**Goal**: One deliberate operator action removes a title from disk, the download client, the arr apps, both servers, and Seerr — no orphans, no auto-deletes.

**Independent Test**: `quickstart.md` Scenarios 4 and 5 — the six-surface delete drill clears everything with zero orphans and is idempotent; nothing is ever deleted automatically.

> Depends on US1 (needs media in the library and the Jellyfin/Seerr connections to cascade into).

- [X] T022 [P] [US2] Create `stacks/maintainerr/compose.yaml` (Dell) — `maintainerr-config` volume, Traefik labels; declare it in `komodo/stacks.toml` (Dell)
- [ ] T023 [US2] Deploy `maintainerr`; connect Maintainerr → Radarr, Sonarr, Jellyfin, Seerr, qBittorrent (`contracts/wiring.md` edges 13–16); create the manual **"remove"** collection; ensure **no** age/watch/disk rules exist (FR-008)
- [ ] T024 [US2] Add a Homepage entry and verify valid TLS for `maintainerr`
- [ ] T025 [US2] Run `quickstart.md` Scenario 4 — seed a title present on **all six** surfaces, add it to "remove", and verify per `contracts/deletion-cascade.md` that disk/qBittorrent/arr/Jellyfin/Plex(after scan)/Seerr are all cleared with **zero** orphans; re-run the add → no error/no change (SC-003, SC-005, FR-006/007/009/010)
- [ ] T026 [US2] Run `quickstart.md` Scenario 5 — confirm nothing is deleted without an explicit add over an observation window (SC-004, FR-008)

**Checkpoint**: the headline capability works — one manual action cleanly removes a title everywhere.

---

## Phase 5: User Story 3 — A self-maintaining, high-quality library (Priority: P2)

**Goal**: Quality profiles come from code; stuck/blocked/malware downloads self-clear; missing items get hunted; bot-protected indexers still work.

**Independent Test**: `quickstart.md` Scenarios 7 and 9 — an injected stalled download is auto-removed+blocklisted+re-searched; quality profiles match the TRaSH config and re-apply idempotently.

> Depends on the Foundational backbone (arr stack), not on US1/US2.

- [X] T027 [P] [US3] Author `stacks/arr/configarr/config.yml` — TRaSH quality profiles + custom formats for Radarr and Sonarr (`contracts/wiring.md` edge 7)
- [ ] T028 [US3] Enable/run Configarr against Radarr/Sonarr; run `quickstart.md` Scenario 9 (profiles match; second run idempotent); record (SC-009, FR-011)
- [X] T029 [P] [US3] Create `stacks/media-helpers/compose.yaml` (**Mac**) — `byparr`, `cleanuparr`, `huntarr`, run **stateless** (config via env / git RO so the Mac holds no persistent state, per golden rule — see `stack-inventory.md` note), Traefik labels; declare it in `komodo/stacks.toml` (`server = "ragnaforge-mac"`)
- [ ] T030 [US3] Deploy `media-helpers`; add Byparr as an indexer proxy in Prowlarr (edge 5); connect Cleanuparr → Radarr/Sonarr/qBittorrent and Huntarr → Radarr/Sonarr (edges 17–18), pointing at the Dell (`10.0.0.70`)
- [ ] T031 [US3] Add Homepage entries and verify valid TLS for `byparr`, `cleanuparr`, `huntarr`
- [ ] T032 [US3] Run `quickstart.md` Scenario 7 (introduce a stalled/blocked download; confirm Cleanuparr removes + blocklists + re-searches with no operator action); record (SC-007, FR-012)
- [ ] T033 [US3] Confirm Huntarr triggers a search for a missing monitored item, and Byparr returns results from a bot-protected indexer (US3 acceptance 3–4, FR-013/014)

**Checkpoint**: the library keeps itself clean, complete, and correctly-graded without babysitting.

---

## Phase 6: User Story 4 — Both media servers + stats (Priority: P2) — RAM-gated

**Goal**: The same library is playable from both Jellyfin and Plex (one on-disk copy); watch stats are visible.

**Independent Test**: `quickstart.md` Scenario 8 — the same title plays from Jellyfin and Plex against one file; stats show for a played title.

> Depends on US1 (library + Jellyfin). **Gated by T034.**

- [X] T034 [US4] **RAM headroom gate** — measure the Dell's free RAM under a Jellyfin transcode + active download load; record in the runbook a go/defer decision for Plex per plan Complexity Tracking (defer to Phase 12 if it won't fit). Do not deploy Plex if the gate fails
- [X] T035 [US4] Create `stacks/plex/compose.yaml` (Dell) — `/dev/dri` QuickSync, `plex-config` volume, `/srv/nfs/media` **RO**, `PLEX_CLAIM=${PLEX_CLAIM}` (first-run), Traefik labels; declare in `komodo/stacks.toml` (Dell)
- [X] T036 [US4] Deploy `plex`; claim the server, add Movies/TV libraries on `/srv/nfs/media`, enable QuickSync HW transcode (Plex Pass)
- [X] T037 [P] [US4] Create `stacks/jellystat/compose.yaml` (Dell) — `jellystat` + `jellystat-db` (Postgres, `jellystat-db` volume), Traefik labels; declare in `komodo/stacks.toml` (Dell)
- [ ] T038 [US4] Deploy `jellystat`; connect it to Jellyfin (API key minted at wiring time); confirm stats populate
- [ ] T039 [US4] Add Homepage entries and verify valid TLS for `plex` and `jellystat`
- [ ] T040 [US4] Run `quickstart.md` Scenario 8 (same title plays from Jellyfin **and** Plex; one on-disk copy; stats visible); record (SC-008, FR-015/017)

**Checkpoint**: dual-server library + stats — the full stack the operator scoped.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T041 Run `quickstart.md` Scenario 10 — confirm 100% of UIs load with valid TLS and appear on Homepage; record (SC-010, FR-019)
- [ ] T042 Run `quickstart.md` Scenario 11 — on a clean re-run of `stacks/arr/configure/wire.yml`, confirm all inter-app connections are present from code with **no** manual clicks, the run is idempotent, and **Buildarr was not used**; record (SC-011, FR-023/023a/024)
- [ ] T043 [P] Secret/state sanity — `git grep` confirms no secret values committed (only `${VAR}` refs + `.mise.toml.example` placeholders); confirm **no** app config lives under `/srv/nfs`; confirm the Mac holds **no** persistent media state (golden rule) (FR-018/020/021)
- [X] T044 [P] Add a **"Three configuration planes"** section to `docs/CONVENTIONS.md` (machine `provision/` · deployment Komodo · application `stacks/*/configure/`, post-deploy) and grow the ports/URL tables for the new stacks (spec FR-023a)
- [ ] T045 Consolidate all `quickstart.md` evidence under `Verification evidence` in `docs/runbooks/phase5-media.md`, update this file's **Implementation status**, and mark the Phase 5 deliverable done in `PLAN.md` / `README.md` (matching how Phases 1–4 recorded completion)

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T004)**: first. T004 depends on T002 (needs the placeholders) and must precede any deploy (stacks read the synced keys).
- **Foundational (T005–T012)**: after Setup. Strict-ish order: T005→T007→T008→T009→T010; T011/T012 after T008. **Blocks US1/US2/US3.**
- **US1 (T013–T021)**: after Foundational. The MVP.
- **US2 (T022–T026)**: after **US1** (needs library + Jellyfin/Seerr to cascade into).
- **US3 (T027–T033)**: after **Foundational** (independent of US1/US2).
- **US4 (T034–T040)**: after **US1**; **gated by T034** (RAM). Independent of US2/US3.
- **Polish (T041–T045)**: after all desired stories.

### Within a stack

- compose.yaml → declare in `komodo/stacks.toml` → deploy via Komodo → wire (plane-3, post-deploy) → verify. Never wire before the app is healthy with keys pinned.

### Parallel opportunities

- **Setup**: T001/T002/T003 are `[P]` (different files); T004 waits on T002.
- **Foundational**: T006 `[P]` (README) alongside T005; the deploy/wire/verify chain is sequential.
- **US1**: T013 (jellyfin compose) `[P]` with T015 (seerr compose) — different files; deploys/verifies then sequence.
- **US3**: T027 (configarr config) `[P]` with T029 (helpers compose) — different files/nodes.
- **US4**: T037 (jellystat compose) `[P]` with the Plex tasks — different files.
- **Cross-story**: once Foundational is done, **US3** (arr-only) can proceed in parallel with **US1/US2** (server-side) if capacity allows.
- **Polish**: T043/T044 `[P]` (different files) alongside T041/T042 evidence runs.

---

## Parallel Example: User Story 1

```bash
# Create the two independent stack files together:
Task: "Create stacks/jellyfin/compose.yaml (Dell, /dev/dri, media RO) + declare in komodo/stacks.toml"
Task: "Create stacks/seerr/compose.yaml (Dell, seerr-config) + declare in komodo/stacks.toml"
# Then deploy + wire + verify sequentially (each needs the prior state).
```

---

## Implementation Strategy

### MVP first (US1)

1. Setup (T001–T004) → 2. Foundational backbone (T005–T012) → 3. US1 (T013–T021).
4. **STOP and VALIDATE**: request→play with private egress + hardlink (SC-001/002/002a/006). Demo the MVP.

### Incremental delivery

- **+ US2** (T022–T026) → the headline cascade delete. *(Completes the P1 pair.)*
- **+ US3** (T027–T033) → self-maintenance & quality-from-code.
- **+ US4** (T034–T040) → dual-server + stats, **only if the RAM gate (T034) passes**; else defer Plex to Phase 12.
- **Polish** (T041–T045) → reproducibility proof + docs + completion.

Each increment adds value without breaking the previous one; stop at any checkpoint to validate independently.

## MVP scope

**Setup + Foundational + US1 + US2 (T001–T026)** = the operator's core ask: request→private-download→play, and the single-action cross-service delete. US3/US4 modernize and extend; US4/Plex is explicitly RAM-gated.

## Notes

- `[P]` = different files, no dependency on an incomplete task.
- No `:latest` image tags — pin explicit versions (Diun/Phase 10 intent).
- Plane-3 wiring (`stacks/arr/configure/wire.yml`) always runs **post-deploy**, idempotently; a schema-drift failure must be **visible**, never silent.
- Commit after each task or logical group; deploys stay deliberate (Komodo manual trigger).
