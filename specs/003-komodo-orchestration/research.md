# Phase 2 Research: Orchestration (Komodo)

The spec was written with the master plan's tool already fixed (Komodo). This
document records the design decisions — grounded in the official Komodo docs
(komo.do) and the `moghtech/komodo` repo — so the tasks phase inherits settled
choices. Version target: **Komodo v2** (`ghcr.io/moghtech/komodo-*:2`).

## R1 — Komodo Core deployment & database

- **Decision**: Deploy **Komodo Core** as a Docker Compose stack on the **Dell**
  from the official compose (image `ghcr.io/moghtech/komodo-core:2`), backed by
  **MongoDB** (the officially recommended DB, `mongo.compose.yaml` variant). Cap
  MongoDB's WiredTiger cache (`--wiredTigerCacheSizeGB`) to a small value
  (~0.5 GB) because the node has only 7.5 GB shared with future stacks.
- **Rationale**: MongoDB is the single-container, officially-supported backend;
  the alternative (FerretDB v2) adds **two** extra containers (FerretDB +
  Postgres/DocumentDB). The Dell's i3-10110U supports AVX2, so modern MongoDB
  runs. Fewer moving parts on a constrained node.
- **Alternatives considered**: **FerretDB v2 on Postgres/DocumentDB** — the
  documented fallback for hosts that can't run modern MongoDB (no AVX); keep it in
  reserve but it's heavier here. Standalone SQLite/Postgres — **deprecated** (that
  was FerretDB v1 under the hood; v1.18/v2 standardized on Mongo-wire backends).
- **Flagged**: no official RAM figures exist; the cache cap is a prudent default
  to validate on the bench.

## R2 — Periphery agent & connection

- **Decision**: Run **Komodo Periphery** on **both** nodes as a **container**
  (`ghcr.io/moghtech/komodo-periphery:2`) from a small bootstrap compose, mounting
  `/var/run/docker.sock` and the stack/repo working dirs. Core connects
  **inbound** to each Periphery on port **8120** (`address =
  "http://10.0.0.7x:8120"`).
- **Rationale**: A pinned container matches the repo ethos (off-the-shelf,
  version-visible, nothing silently outdated) and is consistent with the
  Compose-everywhere model. Inbound is the simplest topology for two trusted LAN
  hosts. Auth in **v2 is PKI** (Ed25519 keypairs + one-time onboarding key), not a
  plaintext shared passkey.
- **Alternatives considered**: **systemd-managed binary via the install script**
  (docs-recommended, simplest) — viable and slightly lighter, but a container
  keeps versioning uniform and avoids a host-level binary to track. Outbound mode
  — only needed behind NAT; not our case.
- **Flagged**: LAN wire-level **TLS** for the Core↔Periphery websocket isn't
  clearly documented (PKI auth is). For a trusted 2-node LAN, `http://…:8120` with
  PKI is the documented norm; revisit `periphery.config.toml` if encryption is
  wanted.

## R3 — Bootstrap model (Core & Periphery are not self-managed at first)

- **Decision**: Core and Periphery are **bootstrapped out-of-band** (they *are*
  the orchestrator, so Komodo can't deploy them from nothing). Ship pinned
  bootstrap compose files under `komodo/bootstrap/` and bring them up with
  `mise exec -- docker compose up -d` (Core on the Dell; Periphery on each node).
  Everything **above** the control plane (the test stack, later apps) is then
  Komodo-managed.
- **Rationale**: Resolves the chicken-and-egg cleanly and keeps the bootstrap
  transparent and reproducible. `mise exec` injects Core's own secrets from the
  gitignored `.mise.toml`.
- **Alternatives considered**: Having Komodo self-adopt Core/Periphery as managed
  stacks after bootstrap (possible later, adds reconfiguration risk now — deferred);
  installing Periphery via the systemd script through Ansible (fine, but splits the
  Komodo story across two tools).

## R4 — Secret injection (the load-bearing decision)

- **Decision**: Keep **`mise` as the single source of secrets**. Two tiers:
  1. **Core's own bootstrap secrets** (DB password, JWT/webhook secrets) → injected
     from `.mise.toml` on the Dell via `mise exec` at Core bring-up.
  2. **Stack secrets** (e.g. later phases' Cloudflare token) → `mise` renders them
     into the **Periphery process environment**; stack `compose.yaml` references
     them as **`${VAR}`**, resolved at deploy time by the Periphery-run compose.
     No real secret value ever appears in the git-synced TOML or compose files.
- **Rationale**: Matches the master plan's "mise-rendered env → Komodo" intent and
  avoids a second secret store. Komodo's Environment/`.env` is materialized next to
  the compose project, so native compose `${VAR}` works on top.
- **Flagged (must bench-validate in quickstart)**: Komodo's native `[[VARIABLE]]`
  interpolation resolves from **Core's DB**, *not* from arbitrary process env — so
  the `${VAR}`-from-Periphery-env path depends on **Periphery forwarding its
  process env into the `docker compose` it invokes**, which the docs don't
  explicitly guarantee. Validate before relying on it.
- **Fallback (documented, robust)**: store the value as a Komodo **secret
  Variable** in Core's DB (redacted from API/logs and **redacted on TOML export**)
  and reference **`[[VAR]]`**; seed the value once from the mise-rendered env. Git
  stays secret-free either way. Note: the `${VAR}` path needs `.mise.toml` present
  on each Periphery node; the `[[VAR]]` fallback keeps secrets only in Core (Dell).

## R5 — Resource Sync (git as the source of truth)

- **Decision**: Declare the fleet in **TOML** under `komodo/` — `servers.toml`
  (`[[server]]` for dell/mac), `stacks.toml` (`[[stack]]` mapping name → target
  `server` → `file_paths` under `stacks/<app>/`), and `variables.toml` (non-secret
  vars only). Point Komodo **ResourceSync** at this git repo; Komodo diffs against
  live state and applies on confirmation.
- **Rationale**: Verified: a `[[stack]]` can pull a git repo and target a specific
  `server` via `stack.config.server` + `file_paths`. This makes git the source of
  truth (FR-003) and reuses the existing `stacks/<app>/compose.yaml` layout the
  Phase-0 README already anticipates.
- **Alternatives considered**: UI-only configuration (not reproducible — rejected);
  "files on host" stacks (needs the repo pre-cloned on each Periphery — more moving
  parts than letting Komodo pull).

## R6 — Deploy workflow (manual default + optional webhook)

- **Decision**: **Manual-trigger** deploys by default — a sync/deploy shows the
  computed diff and requires confirmation. Enable **per-stack git webhooks** only
  where auto-deploy is wanted. A ResourceSync may carry `deploy = true` to
  reconcile-and-deploy in one step.
- **Rationale**: Directly satisfies FR-007 / the master plan's "git is storage +
  history, not a forced deploy button." Verified behavior.
- **Alternatives considered**: Full auto-deploy on every push (rejected as default —
  removes deliberate control; available per-stack when desired).

## R7 — Core exposure & authentication

- **Decision**: Core web UI/API on port **9120**, bound to **LAN/Tailscale only**
  (no router forward, no public DNS). Use built-in **local username/password** with
  a single admin, then **disable open registration**. Public domain + TLS via
  Traefik is **Phase 3**.
- **Rationale**: Satisfies FR-009 (never publicly exposed) without pulling Phase-3
  edge concerns forward. Verified port + auth options (local + optional TOTP/passkey,
  OAuth, OIDC).
- **Alternatives considered**: OIDC/OAuth now (overkill for a single operator; note
  OIDC users aren't auto-provisioned); exposing via Traefik now (deferred to Phase 3).

## R8 — Validation test stack

- **Decision**: Prove orchestration with a **trivial stateless stack** —
  `stacks/whoami/compose.yaml` (`traefik/whoami`, a tiny HTTP echo). Deploy it to
  **both** nodes (as `whoami-dell` / `whoami-mac`, or one stack retargeted) to
  demonstrate per-node placement, without introducing any real app or Traefik.
- **Rationale**: Smallest thing that exercises deploy-to-a-chosen-node, status, and
  logs (US1). Stateless → no golden-rule implications.
- **Alternatives considered**: `nginx`/`docker/welcome-to-docker` (equivalent);
  deploying a real app (out of scope — Phases 3–6).

## R9 — Control-plane state persistence & RAM

- **Decision**: Core's MongoDB data lives in a **named volume on the Dell**
  (stateful → Dell); Core config from `core.config.toml` + `compose.env` (secrets
  via mise). Persistence survives restart (SC-006).
- **Rationale**: Golden rule — the only stateful piece (Core's DB) stays on the
  Dell; the Mac runs a stateless Periphery + stateless test stack, remaining
  disposable.
- **Alternatives considered**: Bind-mount under `/srv/nfs` (unnecessary — Core's DB
  is Dell-local, not shared media); no persistence (loses history/config — rejected).

## Assumptions carried into design

- Both nodes are the **Phase-1 ready Docker hosts** (Docker + compose plugin,
  reachable over LAN/Tailscale; `rushil` in the `docker` group).
- `.mise.toml` (gitignored) holds real secrets; `.mise.toml.example` gains Komodo
  entries (`KOMODO_DB_PASSWORD`, `KOMODO_WEBHOOK_SECRET`, `KOMODO_JWT_SECRET`, plus
  the Core admin bootstrap as needed).
- Debian 13 "trixie" as-built; MongoDB v2 image runs on the Dell's AVX2 CPU.
- The `stacks/` and `komodo/` directories exist (Phase 0) to be filled in.
