---
description: "Task list — Self-Hosted Headscale VPN (replace wg-easy; retire Tailscale SaaS)"
---

# Tasks: Self-Hosted Headscale VPN (replace wg-easy; retire Tailscale SaaS)

**Input**: Design documents from `/specs/011-headscale-vpn/`

**Prerequisites**: plan.md, spec.md, research.md (R1–R11), data-model.md, contracts/ (stack-inventory, remote-access), quickstart.md

**Tests**: This is an infrastructure feature — validation is **behavioural** (SC-001…SC-009 in
`quickstart.md`), not unit tests. No TDD test tasks are generated; the Polish phase runs the SC drills.

**Legend**: `[ ]` = to do. **⏳** = live/operator step (needs the running fleet, real credentials — never
fabricated — a deploy, a router change, or a physical off-LAN/cellular device). Everything else is a
**codified, reproducible-from-git** artifact authorable in the repo.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 (owner remote access — MVP) · US2 (guest onboarding + reliable connect) · US3 (decommission wg-easy / preserve Tailscale)
- Every task names an exact file path or a concrete command target.

## Build order at a glance

1. **Setup** → runbook stub + 1 secret placeholder + Komodo declaration + public DNS name.
2. **Foundational (blocking)** → author the compose (inline `config.yaml` + `policy.hujson`, TLS off, DERP+STUN) → Traefik **forced-HTTP/1.1** router + TLSOption → forward the API-key secret → **deploy + `configtest` + assert (validate BEFORE exposure)** → open **443/tcp + 3478/udp** router forward → Dell joins as the **10.0.0.0/24 subnet router** (auto-approved).
3. **US1 (P1, MVP)** → owner enrolls against Headscale and, **off-LAN**, reaches `*.ragnaforge.xyz` over HTTPS with **no Tailscale-SaaS dependency**.
4. **US2 (P1)** → `guests` user + time-boxed **pre-auth keys** + **least-privilege ACL** + optional **web UI** → a non-technical guest connects **on cellular** (direct or DERP relay).
5. **US3 (P2)** → **DestroyStack wg-easy** + delete files + drop `51820/udp` forward → `tailscale down` (kept installed) → **rollback drill** → relay recipe updated for the new ports.
6. **Polish** → external port scan (only 443+3478; 51820 closed) + no-public-v6 scan + reproducibility/backup + docs.

**Key risk carried from the plan**: Traefik drops Headscale's `tailscale-control-protocol` upgrade over
**HTTP/2** (traefik#12609). Primary fix = TLSOption `alpnProtocols: ["http/1.1"]` on the Headscale
router (T009/T010). If the live handshake still fails on the pinned versions (T017/T020), execute
**Plan B** = Traefik **TCP/SNI passthrough** + Headscale self-TLS (T033).

---

## Implementation status (2026-07-26)

**All 17 codifiable, reproducible-from-git artifacts are DONE** (marked `[X]`): the stack compose +
inline `config.yaml`/`policy.hujson`, the Traefik `headscale-h1` TLSOption + router, the DDNS record, the
`mise` placeholder, the Komodo declaration, the Ansible assert, the runbook (incl. guest onboarding +
Plan B), the `networking-explained.md` rewrite, and the relay recipe. The inline Headscale config was
verified key-for-key against `config-example.yaml @ v0.26.1` (T008).

**The 19 remaining tasks are all `⏳ live/operator` steps** — they need the running fleet, the xFi router,
`docker exec` on the Dell, and physical off-LAN/cellular devices — so they are **not** executable from the
repo. Run them in order per `docs/runbooks/headscale.md`. **Two hard gates:** don't open the router
forward (T015) until the assert (T014) is green; don't retire wg-easy (US3) until US1+US2 pass. **T017 is
the first live proof** the forced-HTTP/1.1 route carries the control handshake — if it fails, execute
Plan B (T033, already documented).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repo scaffolding, the one secret, the Komodo declaration, the public name.

- [X] T001 Create the stack directory and runbook stub: `stacks/headscale/` and `docs/runbooks/headscale.md` (sections: ports/forwarding, deploy, guest onboarding, key rotation/expiry, backup/restore, rollback-to-Tailscale, Plan B passthrough).
- [X] T002 [P] Add the single secret **placeholder** `HEADSCALE_API_KEY` (optional web UI only) to the gitignored `.mise.toml` and document it (name only, no value) in `.mise.toml.example`.
- [X] T003 [P] Declare the stack in `komodo/stacks.toml`: `[[stack]]` name = `headscale`, server = `ragnaforge-dell`, repo/git_provider, `file_paths = ["stacks/headscale/compose.yaml"]`, tags `["phase-3","edge","vpn"]`.
- [X] T004 ⏳ [P] Create the public DNS name `headscale.ragnaforge.xyz` → home public IP: add it to the `cloudflare-ddns` managed record set (Cloudflare A record, DDNS-tracked) so it resolves before any tunnel exists.

**Checkpoint**: Directory, secret placeholder, Komodo decl, and public name exist.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The control plane, its edge wiring, validation, exposure, and the subnet router — all
shared by US1 and US2. **⚠️ No user story work begins until this phase is complete.**

- [X] T005 Author `stacks/headscale/compose.yaml` — service `headscale` (`docker.io/headscale/headscale:<pinned ≤0.26.x>`, container_name `headscale`), `listen_addr 0.0.0.0:8080` (TLS off), on the external `traefik` network, `restart: unless-stopped`, volume `headscale-data:/var/lib/headscale`, and publish STUN bound to the LAN IP: `ports: ["10.0.0.70:3478:3478/udp"]`. Do **not** publish 8080/metrics/grpc to the host. (contracts/stack-inventory)
- [X] T006 Add the inline `configs:` block to `stacks/headscale/compose.yaml` materialising `/etc/headscale/config.yaml`: `server_url: https://headscale.ragnaforge.xyz`, `listen_addr 0.0.0.0:8080`, `metrics_listen_addr`/`grpc_listen_addr` loopback-only, `noise.private_key_path` + DB under `/var/lib/headscale`, `database.type sqlite`, `derp.server.enabled: true` + `region_id` + `stun_listen_addr 0.0.0.0:3478`, `dns.magic_dns: false`, `dns.nameservers.split { "ragnaforge.xyz": ["10.0.0.70"] }`, `prefixes.v4 100.64.0.0/10`, `policy.mode file` → `/etc/headscale/policy.hujson`. (research R4/R9; inline ⇒ recreate on edit)
- [X] T007 Author the inline `policy.hujson` (in the same `configs:` block): users `owner` (acls `*:*`) and `guests` (dst `10.0.0.0/24:443` + `10.0.0.70:53` only), `tagOwners` for `tag:subnet-router`, and `autoApprovers.routes { "10.0.0.0/24": ["tag:subnet-router"] }`. (research R5/R6; contracts/remote-access)
- [X] T008 Verify the pinned tag's config schema: re-diff `config-example.yaml` for the chosen Headscale tag against T006 keys (0.26 vs 0.27 drift) and adjust; record the pinned version in `docs/runbooks/headscale.md`. (research R1)
- [X] T009 Add the Traefik **TLSOption** `headscale-h1` with `alpnProtocols: ["http/1.1"]` to the existing Traefik **file provider** dynamic config. (research R2; [[homeserve-traefik-mac-routing]])
- [X] T010 Add the Traefik router for `headscale`: `Host(headscale.ragnaforge.xyz)` on `websecure`, `tls=true` (wildcard `*.ragnaforge.xyz`), **`tls.options=headscale-h1@file`**, service → `headscale:8080` — as compose labels in `stacks/headscale/compose.yaml`. (research R2)
- [ ] T011 ⏳ Forward the `HEADSCALE_API_KEY` env into the Dell Periphery environment (Komodo) so `${HEADSCALE_API_KEY}` resolves at deploy; generate a real value only when the optional UI (T024) is built.
- [ ] T012 ⏳ Deploy the stack on the Dell via Komodo (DeployStack `headscale`); confirm the container is healthy and the expected `WRN listening without TLS` log appears (benign, TLS is at Traefik).
- [X] T013 Author the Ansible assert `stacks/headscale/configure/assert.yml`: run `headscale configtest`, probe control TLS + liveness at `headscale.ragnaforge.xyz`, STUN reachability on `10.0.0.70:3478`, and route-approval state. Fail closed. (research R10; FR-011/INV-6)
- [ ] T014 ⏳ **Validate BEFORE exposure**: run `docker exec headscale headscale configtest` and `ansible-playbook stacks/headscale/configure/assert.yml`; all green. (quickstart §0)
- [ ] T015 ⏳ Open the **router forwards** on the xFi gateway: `443/tcp` and `3478/udp` → `10.0.0.70`. Keep the gateway on **Typical Security** (no public-v6 exposure). (research R3; INV-1/INV-2)
- [ ] T016 ⏳ Join the **Dell** to its own tailnet as the subnet router: `sudo tailscale up --login-server https://headscale.ragnaforge.xyz --advertise-routes=10.0.0.0/24`; confirm the `10.0.0.0/24` route is **auto-approved** (`headscale nodes list` / `headscale routes list`). (research R5)

**Checkpoint**: Control plane deployed + validated + publicly reachable on 443/3478; the Dell advertises an approved `10.0.0.0/24` route. User stories can begin.

---

## Phase 3: User Story 1 - Owner remote access via Headscale (Priority: P1) 🎯 MVP

**Goal**: The owner, off the home network, reaches every `*.ragnaforge.xyz` app over HTTPS via
self-hosted Headscale, with **zero** dependence on Tailscale's SaaS control plane.

**Independent Test**: Enroll the owner laptop, take it off-LAN (tether to a phone), confirm it tunnels,
resolves `whoami.ragnaforge.xyz` → `10.0.0.70`, and loads it with a valid wildcard cert.

- [ ] T017 ⏳ [US1] Enroll the owner device: `tailscale up --login-server https://headscale.ragnaforge.xyz` (create an `owner` user + key first via `headscale users create owner` / `headscale preauthkeys create --user owner`); confirm the node in `headscale nodes list`. **This is the first live proof the forced-HTTP/1.1 router carries the control handshake** — if it fails, go to T033 (Plan B). (quickstart §1)
- [ ] T018 ⏳ [US1] From the enrolled owner device **on the LAN**, verify split DNS + route: `whoami.ragnaforge.xyz` resolves to `10.0.0.70` and loads over HTTPS; `tailscale status` shows Headscale peers (not `*.ts.net`). (FR-005/FR-007)
- [ ] T019 ⏳ [US1] Take the owner device **off-LAN** (phone tether); confirm cold-connect tunnel + `curl -I https://whoami.ragnaforge.xyz` = 200 with valid cert in **<30 s** (SC-001), and that **no session depends on Tailscale SaaS** (SC-004).
- [ ] T020 ⏳ [US1] Force a **relay-only** path (block STUN/UDP on the test network) and confirm the app still loads via embedded DERP (owner-side proof of FR-008 before guests rely on it). (quickstart §2)

**Checkpoint**: Owner has reliable, fully self-hosted remote access — the MVP is demonstrable.

---

## Phase 4: User Story 2 - Guest onboarding + reliable connect (Priority: P1)

**Goal**: A non-technical guest joins with one paste/scan and connects reliably from cellular (direct or
DERP relay), scoped to the edge only — replacing the failing wg-easy.

**Independent Test**: Send a guest a time-boxed key; they enroll on a phone (app only) and reach a
shared app on **cellular**, but cannot reach fleet internals.

- [ ] T021 ⏳ [US2] Create the `guests` user and a **single-use, time-boxed** pre-auth key: `headscale users create guests` then `headscale preauthkeys create --user guests --expiration 24h` (add `--reusable` only for a shared family device). (research R7; FR-006/FR-010)
- [X] T022 [US2] Write the **guest onboarding guide** in `docs/runbooks/headscale.md`: per-platform custom-coordination-server steps (Android/Windows/Linux/macOS CLI + iOS/macOS app field), pasting the key, and re-auth on key expiry; note the Fire-TV-class gap. (research R7; FR-019)
- [ ] T023 ⏳ [US2] Onboard a **real guest device on cellular (WiFi off)** using only the app + key; time it (**<5 min**, SC-002); open a shared `*.ragnaforge.xyz` app over HTTPS — the case wg-easy failed. (quickstart §2; SC-003)
- [X] T024 [P] [US2] (Optional, R8) Add the `headscale-ui` service to `stacks/headscale/compose.yaml`: `ghcr.io/gurucomputing/headscale-ui`, `HEADSCALE_API_KEY` from `${HEADSCALE_API_KEY}`, Traefik route `headscale-ui.ragnaforge.xyz` (normal wildcard, **LAN/VPN-only — never forwarded**). (contracts/stack-inventory)
- [ ] T025 ⏳ [US2] Verify **ACL scoping**: from the guest device `curl -I https://<shared-app>.ragnaforge.xyz` = 200, but `ssh 10.0.0.70` and `curl http://10.0.0.70:3000` (AdGuard admin) are blocked. (research R6; FR-009; quickstart §3)

**Checkpoint**: Guests onboard simply and connect reliably on cellular, scoped to the edge.

---

## Phase 5: User Story 3 - Decommission wg-easy; preserve Tailscale as rollback (Priority: P2)

**Goal**: Remove wg-easy and its public port cleanly; keep Tailscale installed but stopped, with a
one-command rollback proven.

**Independent Test**: wg-easy stack/UI/port gone and unreachable; `tailscale up` on the Dell restores the
old owner path in minutes.

- [ ] T026 ⏳ [US3] DestroyStack `wg-easy` in Komodo, then delete `stacks/wg-easy/` and remove its `[[stack]]` decl from `komodo/stacks.toml` and its `wg.ragnaforge.xyz` route. (research R11; contracts/stack-inventory)
- [ ] T027 ⏳ [US3] Remove the **`51820/udp`** forward from the xFi router; confirm externally it is closed. (SC-006)
- [ ] T028 ⏳ [US3] Stop the Dell's Tailscale SaaS session (`sudo tailscale down`) **without** uninstalling; confirm the client + tailnet identity remain intact. (FR-003)
- [ ] T029 ⏳ [US3] **Rollback drill**: `sudo tailscale up` re-points the Dell to Tailscale SaaS and restores the prior owner path in **<10 min** with no re-provision; then return to Headscale (re-run T016). (FR-017; SC-007)
- [X] T030 [US3] Update `relay/README.md` (NO-GO fallback): DNAT **443/tcp + 3478/udp** to the Dell **over the preserved Tailscale tailnet** (replacing the old 51820 DNAT); doc only. (research R11; FR-016)

**Checkpoint**: Old VPN fully retired; Tailscale is a stopped, proven fallback.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Prove the invariants and finish the docs.

- [ ] T031 ⏳ [P] **External port scan** from off-network: only `443/tcp` + `3478/udp` open; `51820/udp` closed. (SC-005/SC-006; INV-1)
- [ ] T032 ⏳ [P] **No-public-v6 scan**: `nmap -6` of the Dell's public v6 shows no new service (AdGuard :53/:3000, Komodo, SSH, NFS all closed). (SC-009; INV-2)
- [X] T033 [P] Document **Plan B** in `docs/runbooks/headscale.md`: Traefik TCP router `tls.passthrough=true` on `HostSNI(headscale.ragnaforge.xyz)` + Headscale self-TLS (TLS-ALPN-01), when/how to switch. (research R2)
- [X] T034 [P] Rewrite the wg-easy scenario in `docs/networking-explained.md` as the Headscale flow and replace the port table (`51820/udp` → `443/tcp + 3478/udp`). (FR-018/FR-019)
- [ ] T035 ⏳ [P] **Backup/restore + reproducibility** drill: snapshot `headscale-data`, destroy+redeploy the stack from git, restore the volume, confirm nodes/keys return with no undocumented step. (SC-008; quickstart §6)
- [X] T036 [P] Final runbook pass: pinned version, ports/forwarding, key rotation, backup/restore, rollback, Plan B, ACL vhost-scoping limitation all present in `docs/runbooks/headscale.md`.

---

## Dependencies & story completion order

- **Setup (T001–T004)** → **Foundational (T005–T016)** blocks everything.
- **US1 (T017–T020)** depends only on Foundational — **the MVP**.
- **US2 (T021–T025)** depends on Foundational; independent of US1 (can start once T016 is done), but US1's T020 de-risks the relay path US2 relies on.
- **US3 (T026–T030)** depends on US1 **and** US2 being proven (don't retire wg-easy until Headscale works for owner + guests).
- **Polish (T031–T036)** last.

## Parallel opportunities

- Setup: T002, T003, T004 in parallel.
- Foundational: T009/T010 (Traefik) parallel to T005–T007 (compose/config) authoring; T013 assert authorable alongside. Live steps T012→T014→T015→T016 are sequential.
- US2: T022 (guide) and T024 (optional UI) `[P]` alongside the live enroll steps.
- Polish: T031–T036 largely independent `[P]`.

## Implementation strategy

- **MVP = Setup + Foundational + US1.** Delivers fully self-hosted owner remote access on 443/3478 with
  the friendly-name/cert experience intact — demonstrable before touching guests or wg-easy.
- **Increment 2 = US2**: guest onboarding + ACL + optional UI.
- **Increment 3 = US3 + Polish**: retire wg-easy, prove rollback, lock down and document.
- **Do not open the router forward (T015) until validation (T014) is green** (fail-closed, INV-6). **Do
  not run US3 (retire wg-easy) until US1+US2 pass.**
