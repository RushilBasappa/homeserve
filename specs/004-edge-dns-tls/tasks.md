---
description: "Task list — Phase 3: Edge, DNS & TLS"
---

# Tasks: Phase 3 — Edge, DNS & TLS

**Input**: Design documents from `/specs/004-edge-dns-tls/`

**Prerequisites**: plan.md, spec.md (8 user stories), research.md (R1–R12),
data-model.md (12 edge entities), contracts/ (4 contracts), quickstart.md (SC-001…14)

**Tests**: This is an infrastructure phase — validation is **behavioral** (see
`quickstart.md`), not a unit suite. No TDD test tasks were requested; each user-story
phase ends with the behavioral verification from `quickstart.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US8 from spec.md; Setup/Foundational/Polish carry no story label
- Every capability is a **Komodo-managed stack on the Dell** (`server =
  "ragnaforge-dell"`), declared in `komodo/` and deployed from Core (FR-013). Stacks
  follow `docs/CONVENTIONS.md` (stack = dir = subdomain = Homepage entry).

## Build order at a glance

Setup → Foundational (network + Dell host prep) → **US3** Traefik+cert (substrate) →
**US1** app reachable → **US2** publish-by-labels → **US4** AdGuard DNS → **US5**
Homepage → **US7** preflight → **US6** DDNS → **US8** wg-easy (gated on US7) → Polish.
US6 (P3) is sequenced before US8 (P2) because US8 depends on it — see Dependencies.

---

## Implementation status (2026-07-19)

All **git-declared artifacts are authored and validated statically** (YAML/TOML
parse-checked; the secret-free grep is clean; the preflight script passes
`bash -n`): every stack compose + config, the Traefik static config, the AdGuard
first-run guide, the Homepage config, the preflight script, the relay recipe, the
Komodo stack declarations, the `edge-dns.yml` provision task + playbook wiring, the
`make edge-network`/`make preflight` targets, and the runbook/README/CONVENTIONS
docs. Those tasks are marked `[X]`.

The remaining unchecked tasks are **deploy-and-verify steps that require the live
Dell, the xFi gateway, and external/off-network devices** — they cannot be done
from the authoring environment. Each is tagged **⏳ operator** below and has its
run-and-verify procedure in [`../../docs/runbooks/phase3-edge.md`](../../docs/runbooks/phase3-edge.md).
For the four "declare + deploy" tasks (T020/T024/T029/T034) the **declaration in
`komodo/stacks.toml` is done**; only the deploy-from-Core + verify half remains.

---

## Phase 1: Setup

**Purpose**: git-safe secrets/variables and the runbook skeleton — no services yet.

- [X] T001 Add new secret placeholders to `.mise.toml.example`: `WG_EASY_PASSWORD_HASH` (bcrypt) and `ADGUARD_ADMIN_PASSWORD`, with a comment noting `CLOUDFLARE_API_TOKEN` (already present) is reused for Traefik DNS-01 + DDNS (research R12; FR-014)
- [X] T002 [P] Add non-secret `[[variable]]` entries to `komodo/variables.toml`: `VPN_HOSTNAME=vpn.ragnaforge.xyz` (and any edge hostnames); confirm `FLEET_DOMAIN`, `DELL_LAN_IP` already exist (research R12)
- [X] T003 [P] Create runbook skeleton `docs/runbooks/phase3-edge.md` with the bring-up order sections from research R11 (to be filled as stacks land)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: shared substrate every edge stack needs. **⚠️ No user story can start until
this is done.**

- [X] T004 Add a `make edge-network` target (Makefile) that creates the external Docker network `traefik` on the Dell (`docker network create traefik`, idempotent); document it in `docs/runbooks/phase3-edge.md` (research R10; data-model §10)
- [X] T005 Free `:53` on the Dell for AdGuard: add `provision/tasks/edge-dns.yml` (disable the `systemd-resolved` DNS stub listener / point resolv.conf appropriately), wire it into `provision/playbook.yml`, and document the manual equivalent in the runbook (research R3)
- [X] T006 [P] Ensure `net.ipv4.ip_forward=1` on the Dell for wg-easy NAT — add to the Phase-1 `provision/tasks/sysctl.yml` (or a new task) and note in the runbook (research R6)

**Checkpoint**: `traefik` network exists on the Dell; `:53` is free; IP forwarding on.

---

## Phase 3: User Story 3 — Automatic browser-trusted certificates (Priority: P1) 🎯 MVP substrate

**Goal**: Traefik up with a persisted, auto-renewing wildcard `*.ragnaforge.xyz` cert
from Let's Encrypt via Cloudflare DNS-01 — the routing + TLS foundation everything else
reuses.

**Independent Test**: from a fresh `traefik-acme` volume, Traefik obtains a valid
LE-issued `*.ragnaforge.xyz` cert unattended; a restart does **not** re-issue.
(SC-001/004/007; contract `tls-certificate-contract.md`)

- [X] T007 [US3] Create `stacks/traefik/compose.yaml`: `traefik:v3`, on the `traefik` external network, ports `80`+`443`, `traefik-acme` named volume (Dell), env `CF_DNS_API_TOKEN=${CLOUDFLARE_API_TOKEN}`; no public admin dashboard (research R1/R2; data-model §1)
- [X] T008 [US3] Add Traefik static config `stacks/traefik/traefik.yaml` (or CLI args): entryPoints `web`/`websecure`, Docker provider (exposedByDefault=false), and a `certificatesResolvers` using `dnsChallenge` provider `cloudflare` requesting wildcard `main: ragnaforge.xyz`, `sans: *.ragnaforge.xyz` (research R2; contract `tls-certificate-contract.md`)
- [X] T009 [US3] Add the global HTTP→HTTPS redirect (entryPoint `web` redirection to `websecure`) via static config or `stacks/traefik/dynamic/redirect.yaml` (research R1; FR-004)
- [X] T010 [US3] Declare the traefik stack in `komodo/stacks.toml` (`[[stack]]` → `server = "ragnaforge-dell"`, `file_paths=["stacks/traefik/compose.yaml"]`, `webhook_enabled=false`) (FR-013; data-model §11)
- [ ] T011 [US3] ⏳ **operator** — Deploy traefik from Komodo Core; verify the wildcard cert issues (logs; `acme.json` present, perms `0600`), restart the stack and confirm **no** re-issuance (quickstart Scenario 1; SC-007)

**Checkpoint**: wildcard cert live and persisted; the proxy is ready to route.

---

## Phase 4: User Story 1 — Reach any app at a friendly HTTPS name (Priority: P1)

**Goal**: a deployed stack is reachable at `https://<name>.ragnaforge.xyz` with a
trusted cert.

**Independent Test**: `https://whoami.ragnaforge.xyz` loads over trusted HTTPS with no
warning; `http://` redirects; an unclaimed host returns 404. (SC-001/006; contract
`edge-routing-contract.md`) — before AdGuard (US4), resolve the name with a temporary
hosts-file/`--resolve` override; US4 makes it seamless.

- [X] T012 [US1] Add the canonical Traefik labels to `stacks/whoami/compose.yaml` (router/service = `whoami`, `Host(\`whoami.ragnaforge.xyz\`)`, `entrypoints=websecure`, `tls=true`, `server.port=80`) and attach the `traefik` network; remove any host `ports:` (research R1; contract `edge-routing-contract.md`)
- [ ] T013 [US1] ⏳ **operator** — Redeploy `whoami` from Komodo; with a temporary `whoami.ragnaforge.xyz → 10.0.0.70` hosts override, verify HTTPS loads with the wildcard cert (no warning) within ~30 s (quickstart Scenario 3; SC-002)
- [ ] T014 [US1] ⏳ **operator** — Verify `http://whoami.ragnaforge.xyz` redirects to `https://`, and `https://nope.ragnaforge.xyz` returns a clear 404 (not a wrong app) (SC-006)

**Checkpoint**: an app is reachable by friendly HTTPS name.

---

## Phase 5: User Story 2 — Publishing a new app is just labels + a DNS name (Priority: P1)

**Goal**: prove a new/changed route needs only labels — no Traefik config edit, no new
cert — and stale routes disappear.

**Independent Test**: adding labels to a second route makes it live within seconds
without touching Traefik config or issuing a cert; stopping the stack drops the route.
(SC-002/003; contract `edge-routing-contract.md`)

- [X] T015 [US2] Codify the label contract as the reusable pattern: confirm `docs/CONVENTIONS.md` "Traefik routing labels" matches the deployed reality; adjust if drifted (contract `edge-routing-contract.md`)
- [ ] T016 [US2] ⏳ **operator** — Prove publish-by-labels: add a second router (e.g. a `whoami2` host rule or a temporary second labelled service), deploy, and confirm it is served under the **existing** wildcard with **no** Traefik config edit and **no** new issuance (SC-003)
- [ ] T017 [US2] ⏳ **operator** — Prove teardown: stop the labelled stack and confirm its route stops responding within seconds (no stale route); revert the temporary second route (FR-002)

**Checkpoint**: the label-only publish workflow every later phase reuses is proven.

---

## Phase 6: User Story 4 — Names resolve on the LAN and follow VPN clients (Priority: P1)

**Goal**: AdGuard answers `*.ragnaforge.xyz → 10.0.0.70` for every client, forwards the
rest, and blocks ads — making US1 seamless without hosts overrides.

**Independent Test**: a device using `10.0.0.70` resolves every `*.ragnaforge.xyz` to
`10.0.0.70`, public domains still resolve, a known ad domain is blocked. (SC-005;
contract `dns-resolution-contract.md`)

- [X] T018 [US4] Create `stacks/adguard/compose.yaml`: AdGuard Home, ports `53/tcp`+`53/udp` on the Dell, `adguard-conf`+`adguard-work` volumes; admin UI bound **LAN/Tailscale-only** (not the public port) (research R3; data-model §4; FR-016)
- [X] T019 [US4] Configure AdGuard: DNS **rewrite** `*.ragnaforge.xyz → 10.0.0.70`, upstream resolvers (Quad9/Cloudflare, DNSSEC), and ad/tracker blocklists; capture config in the stack (or document first-run steps + `ADGUARD_ADMIN_PASSWORD`) (research R3; FR-008/010)
- [ ] T020 [US4] ⏳ **operator** — Declaration DONE in `komodo/stacks.toml` (→ `ragnaforge-dell`); remaining: deploy from Core (data-model §11; FR-013)
- [ ] T021 [US4] ⏳ **operator** — Point a test device's DNS at `10.0.0.70`; verify `*.ragnaforge.xyz → 10.0.0.70`, a public domain resolves, an ad domain is blocked, and `https://whoami.ragnaforge.xyz` now loads with **no** hosts override (quickstart Scenario 2; SC-005). Remove the temporary hosts override from T013

**Checkpoint**: friendly names resolve network-wide; ad-blocking active.

---

## Phase 7: User Story 5 — One front door lists every app (Priority: P2)

**Goal**: Homepage dashboard at `https://home.ragnaforge.xyz` linking to apps.

**Independent Test**: `https://home.ragnaforge.xyz` loads over trusted HTTPS and shows
a working link to at least one deployed app. (SC-001; data-model §6)

- [X] T022 [P] [US5] Create `stacks/homepage/compose.yaml` (gethomepage/homepage) with the canonical Traefik labels for `home.ragnaforge.xyz`, `homepage-config` volume on the Dell (research R5; contract `edge-routing-contract.md`)
- [X] T023 [P] [US5] Add `stacks/homepage/config/*.yaml` (settings + services/bookmarks) listing `whoami` and placeholders for later apps; optional Docker-label service discovery (research R5)
- [ ] T024 [US5] ⏳ **operator** — Declaration DONE in `komodo/stacks.toml`; remaining: deploy from Core; verify `https://home.ragnaforge.xyz` loads over trusted HTTPS with a working app link (quickstart Scenario 4; SC-001)

**Checkpoint**: the front door is live.

---

## Phase 8: User Story 7 — Preflight: can the home host a public VPN endpoint? (Priority: P2, runs BEFORE US8)

**Goal**: a checks-first GO/NO-GO that decides US8's direct-forward vs relay path.

**Independent Test**: `make preflight` prints a clear GO or NO-GO (public-IP-vs-CGNAT,
external UDP-51820 reachability, DDNS resolution); inconclusive ⇒ NO-GO (no false GO).
(SC-013; contract `remote-access-contract.md`)

- [X] T025 [US7] Create `scripts/preflight-public-endpoint.sh`: fetch external IP, flag CGNAT (`100.64.0.0/10` / external-IP mismatch), probe external UDP 51820, check `vpn.ragnaforge.xyz` resolves; emit a single GO/NO-GO with reason; inconclusive ⇒ NO-GO (research R7; FR-021)
- [X] T026 [US7] Add a `make preflight` target invoking the script; document how to run the external-vantage probe (phone hotspot / external checker) in `docs/runbooks/phase3-edge.md`
- [ ] T027 [US7] ⏳ **operator** — Run `make preflight` and **record the verdict** in the runbook — it selects the direct-forward (GO) or cloud-relay (NO-GO) path for Phase 10 (quickstart Scenario 0; SC-013)

**Checkpoint**: the go/no-go for public exposure is known and recorded.

---

## Phase 9: User Story 6 — Public DDNS record tracks the home IP (Priority: P3, prerequisite for US8 direct path)

**Goal**: keep `vpn.ragnaforge.xyz` on the current public IP (direct path only).

**Independent Test**: `vpn.ragnaforge.xyz` (Cloudflare) is set to the current public IP
within the configured interval; an unchanged IP makes no needless update. (SC-008)

- [X] T028 [US6] Create `stacks/cloudflare-ddns/compose.yaml` (favonia/cloudflare-ddns): `CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}`, `DOMAINS=vpn.ragnaforge.xyz`, `PROXIED=false`, interval; stateless (research R4; data-model §5)
- [ ] T029 [US6] ⏳ **operator** — Declaration DONE in `komodo/stacks.toml`; remaining: deploy from Core; verify `vpn.ragnaforge.xyz` updates to the current public IP (quickstart Scenario 5; SC-008). NOTE: on the relay (US8 NO-GO) path this stack is unnecessary — the VPS IP is static

**Checkpoint**: the VPN endpoint name tracks the dynamic home IP.

---

## Phase 10: User Story 8 — Remote family/friend over the secondary VPN (Priority: P2)

**Goal**: wg-easy reachable at `vpn.ragnaforge.xyz` via the **one** public UDP port
(direct or relayed per US7), pushing DNS + subnet route so remote clients reach apps;
only that port is public.

**Independent Test**: an off-LAN/off-Tailscale device with a fresh `.conf` connects and
loads an app over trusted HTTPS; the same app also loads over Tailscale; a public scan
shows only UDP 51820. (SC-010/011/012/014; contract `remote-access-contract.md`)

- [X] T030 [US8] Create `stacks/wg-easy/compose.yaml`: `WG_HOST=vpn.ragnaforge.xyz`, `WG_DEFAULT_DNS=10.0.0.70`, `WG_ALLOWED_IPS` incl. `10.0.0.0/24`, `PASSWORD_HASH=${WG_EASY_PASSWORD_HASH}`, publish **`51820/udp`**, admin `51821/tcp` bound **LAN/Tailscale-only**, `wg-easy-config` volume on the Dell (research R6; data-model §7; FR-015/16/17/18)
- [ ] T031 [US8] ⏳ **operator** — Advertise the LAN subnet to Tailscale clients: `tailscale up --advertise-routes=10.0.0.0/24` on the Dell, approve the route in the Tailscale admin, and confirm operator devices `--accept-routes` (research R9; FR-019)
- [ ] T032 [US8] ⏳ **operator** — **GO path** (per T027): forward **only** UDP 51820 → the Dell on the xFi gateway; document the exact xFi steps in the runbook (FR-015)
- [X] T033 [P] [US8] **NO-GO path** (per T027): stand up the cloud relay from `relay/README.md` (VPS on the tailnet, nftables/socat DNAT `51820/udp` → Dell Tailscale IP), and point `vpn.ragnaforge.xyz` at the VPS static IP (research R8; FR-022). Skip if T027 was GO
- [ ] T034 [US8] ⏳ **operator** — Declaration DONE in `komodo/stacks.toml`; remaining: deploy from Core; create a client config in the wg-easy admin (LAN/Tailscale only) (data-model §11)
- [ ] T035 [US8] ⏳ **operator** — From a device off-LAN and off-Tailscale (e.g. phone hotspot), import the `.conf`, connect via `vpn.ragnaforge.xyz`, and verify `https://whoami.ragnaforge.xyz` + `https://home.ragnaforge.xyz` load over trusted HTTPS; confirm the same app also loads over Tailscale (quickstart Scenario 6; SC-011/012)
- [ ] T036 [US8] ⏳ **operator** — Port-scan the home's public IP from an external vantage and confirm **only UDP 51820** responds — no app, dashboard, resolver, Traefik/AdGuard/wg-easy admin reachable off-LAN (quickstart Scenario 7; SC-010; FR-016)

**Checkpoint**: private remote access works over both VPN paths; exactly one port public.

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: prove the invariants and update the shareable docs.

- [X] T037 Run the secret-free check (quickstart Scenario 8): grep `komodo/` + `stacks/` for real values / the live token; confirm only `${VAR}`/`[[VAR]]` refs and that a fresh clone + filled `.mise.toml` reproduces the edge from Core (SC-009)
- [X] T038 [P] Update the Ports table in `docs/CONVENTIONS.md` with the now-live allocations (80/443 traefik, 53 adguard, 51820 wg-easy) and confirm the "no host ports for HTTP apps" rule held
- [X] T039 [P] Complete `docs/runbooks/phase3-edge.md`: bring-up order, `:53` + ip_forward prep, cert issuance, preflight verdict + chosen path, and family/friend VPN onboarding (incl. Fire TV file import)
- [X] T040 [P] Update the README "Phase 3 — Edge, DNS & TLS" section from _Not started_ to ✅ with the delivered capabilities and the one-line flow (resolver → subnet route → Traefik → wildcard cert)
- [X] T041 Remove the throwaway `whoami` route/labels once a real app exists, or leave clearly marked as the Phase-3 proof (mirrors the Phase-2 whoami note); update Homepage + `komodo/stacks.toml` accordingly

---

## Dependencies

- **Setup (T001–T003)** → no deps.
- **Foundational (T004–T006)** → blocks all stories. T004 (network) blocks Traefik/apps;
  T005 (`:53`) blocks AdGuard; T006 (ip_forward) blocks wg-easy.
- **US3 (Traefik+cert)** → after Foundational. Substrate for US1/US2/US5 (all need the
  proxy + wildcard cert).
- **US1** → after US3. Fully seamless only after **US4** (DNS); testable earlier via a
  hosts override.
- **US2** → after US3 (proves the label workflow; independent of DNS).
- **US4 (AdGuard)** → after T005; completes US1's browse-by-name.
- **US5 (Homepage)** → after US3 (needs routing + cert).
- **US7 (Preflight)** → after Setup; **must precede US8** (selects its path).
- **US6 (DDNS)** → after Setup; **prerequisite for US8's direct (GO) path** (skip on the
  relay path). Sequenced before US8 despite its P3 priority.
- **US8 (wg-easy)** → after US7 (verdict), US6 (GO path) or relay (NO-GO), US4 (client
  DNS target), and the Tailscale subnet route (T031).
- **Polish (T037–T041)** → after the stories it documents.

## Parallel opportunities

- **Setup**: T002, T003 in parallel (T001 touches `.mise.toml.example` alone).
- **Foundational**: T006 in parallel with T004/T005.
- **Stack authoring across stories** (different files, before their deploy/verify): the
  compose/config authoring tasks T022+T023 (Homepage), T025 (preflight), T028 (DDNS),
  and T030 (wg-easy) can be written in parallel once Foundational is done — but each
  **deploy/verify** step still follows its dependency order above.
- **US8 paths**: T032 (GO) and T033 (NO-GO) are mutually exclusive — do the one T027
  selected.
- **Polish**: T038, T039, T040 in parallel.

## Implementation strategy

- **MVP = US3 → US1 → US4** (Traefik + wildcard cert + an app reachable by a resolving
  HTTPS name). That alone delivers the phase's headline: `https://home.ragnaforge.xyz`
  (add US5) loads with a trusted cert on the LAN. Ship it, then layer the VPN slice.
- **Increment 2 = US2 + US5**: prove the reusable publish workflow and stand up the
  dashboard front door.
- **Increment 3 (VPN slice) = US7 → US6 → US8**: run the preflight first, then the
  reachability path it selected, then wg-easy — the only increment that touches public
  exposure, and the only one that might pull in the conditional relay.
- Deploy every stack **from Komodo Core** (git-declared), never hand-configured on the
  node; keep the tree secret-free throughout.
