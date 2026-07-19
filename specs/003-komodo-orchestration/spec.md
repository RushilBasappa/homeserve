# Feature Specification: Phase 2 — Orchestration (Komodo)

**Feature Branch**: `003-komodo-orchestration`

**Created**: 2026-07-19

**Status**: Draft

**Input**: User description: "start phase 2"

## Overview

Phase 1 produced two clean, ready Docker hosts. Phase 2 turns them into a
**centrally managed fleet**: one control plane from which the operator defines
and deploys Docker Compose stacks to either node, with the fleet's desired state
(which servers exist, which stacks run where) declared in the **git repository**
and secrets injected from the gitignored `.mise.toml` — never committed.

This phase delivers the **orchestration capability**, not the applications. No
end-user services (reverse proxy, media, photos, etc.) are stood up here — those
are Phases 3–6. Phase 2 is proven by deploying a **minimal test stack** to each
node from the control plane alone. The "user" throughout is the **operator**
reproducing and running the server.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy a stack to either node from one place (Priority: P1)

As the operator, I can deploy a Docker Compose stack to **either** node
(`ragnaforge-dell` or `ragnaforge-mac`) from a single control plane — its web UI
or CLI/API — so I manage the whole fleet centrally instead of SSHing into each
box and running Compose by hand.

**Why this priority**: This is the phase's core deliverable and the foundation
every later phase deploys onto. Without central deploy, every subsequent app
becomes manual per-host work.

**Independent Test**: With the control plane up and both nodes registered, deploy
a test stack targeting one node from the control plane; confirm its container
runs on that node and its status is visible centrally — with no manual SSH or
`docker compose` on the node.

**Acceptance Scenarios**:

1. **Given** the control plane and both nodes registered as managed servers,
   **When** the operator triggers a deploy of a test stack targeting a specific
   node, **Then** the stack's container(s) run on that node and report healthy in
   the control plane.
2. **Given** a deployed stack, **When** the operator views the control plane,
   **Then** they see the stack's status and can read its logs without connecting
   to the node directly.
3. **Given** a stack targeting the Mac, **When** it is deployed, **Then** it runs
   on the Mac and not the Dell (placement follows the declaration).

---

### User Story 2 - Fleet defined declaratively in git (Priority: P1)

As the operator, the servers and stacks are **declared in the git repo** (under
`komodo/`) and the control plane syncs from those declarations, so the fleet's
desired state is version-controlled and reproducible rather than click-configured
and forgotten.

**Why this priority**: Reproducibility ("a competent friend could rebuild it") is
the project's north star; the fleet definition must live in git, not only in the
control plane's database.

**Independent Test**: Commit a server/stack definition under `komodo/`, run a sync
from the control plane, and confirm the defined server/stack appears and is
deployable; change a definition in git, re-sync, and confirm the change is
reflected.

**Acceptance Scenarios**:

1. **Given** server and stack definitions committed under `komodo/`, **When** the
   control plane syncs from the repo, **Then** exactly those servers and stacks
   appear as managed resources.
2. **Given** a change to a stack definition in git, **When** the operator syncs,
   **Then** the control plane reflects the change (and flags what would deploy).
3. **Given** the control plane's live state, **When** compared to the git
   declarations, **Then** git is the source of truth for servers and stack
   mappings.

---

### User Story 3 - Secrets come from mise, never git (Priority: P1)

As the operator, stacks receive their secrets from the `mise`-rendered
environment, referenced by name in git — never as literal values — so credentials
never leak into the repository while stacks still get exactly what they need.

**Why this priority**: A leaked secret in a shareable repo is a
security/privacy failure; the whole project is designed to be shareable, so
secret hygiene is non-negotiable.

**Independent Test**: Deploy a stack that consumes a secret variable; confirm the
value is injected from the `mise`-rendered env at deploy time and that no real
secret value appears in any tracked file.

**Acceptance Scenarios**:

1. **Given** a stack referencing a secret by name, **When** it is deployed,
   **Then** the value is supplied from the `mise`-rendered environment.
2. **Given** the tracked repository, **When** inspected, **Then** no real secret
   value appears in any committed file (only placeholders/references).
3. **Given** a required secret is missing from the environment, **When** a deploy
   is attempted, **Then** it fails with a clear error rather than deploying with
   an empty/blank value.

---

### User Story 4 - Deliberate deploy workflow (Priority: P2)

As the operator, deploys happen on a **manual trigger** by default — git is
storage and history, not a deploy button I'm forced to press — with the option to
enable per-stack auto-deploy (webhook) where I want it, so I control when changes
go live.

**Why this priority**: Valuable control over change timing, but subordinate to
simply being able to deploy centrally (US1) and declare in git (US2).

**Independent Test**: With auto-deploy disabled, commit a change and confirm
nothing deploys until a manual trigger; then enable a per-stack webhook and
confirm that stack auto-deploys on the next change.

**Acceptance Scenarios**:

1. **Given** a synced stack with auto-deploy off, **When** a change is committed
   and nothing is triggered, **Then** the running stack is unchanged until a
   manual deploy.
2. **Given** the operator triggers a deploy (UI or CLI), **When** it runs,
   **Then** the stack converges to the declared state.
3. **Given** a per-stack webhook is enabled, **When** a relevant change lands,
   **Then** that stack deploys automatically while others remain manual.

---

### Edge Cases

- **Control-plane host restarts/reboots**: the control plane's state (servers,
  stacks, history, config) persists and agents reconnect — no manual re-setup.
- **A node is offline when a deploy is triggered**: the offline node is reported;
  deploying to the reachable node still works (independent per node).
- **A stack declaration references a missing directory or secret**: surfaced as a
  clear error, not a silent or partial deploy.
- **Adding a third node later**: register its agent and add its server definition
  in git; existing servers/stacks are unaffected (add/remove is a config change).
- **Removing a node**: its stacks are reassigned to another node; the rest of the
  fleet keeps working.
- **Control-plane admin interface accidentally reachable publicly**: it must be
  bound to the LAN/personal VPN only, never the public internet.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a single control plane on the Dell — with a
  web UI **and** programmatic (CLI/API) access — for managing both nodes.
- **FR-002**: The system MUST run a management agent on **each** node
  (`ragnaforge-dell`, `ragnaforge-mac`) so both are controllable from the control
  plane.
- **FR-003**: The fleet's **servers and stacks MUST be declared in the git repo**
  (under `komodo/`), and the control plane MUST sync from those declarations as
  the source of truth.
- **FR-004**: The operator MUST be able to deploy any declared Compose stack to a
  chosen node from the control plane (UI or CLI) with **no** manual SSH or
  `docker compose` on the node.
- **FR-005**: The control plane MUST show each stack's deploy status/health and
  provide access to its logs centrally.
- **FR-006**: Secrets MUST be injected into stacks from the `mise`-rendered
  environment; **no real secret value** may appear in any tracked file (only
  placeholders/references).
- **FR-007**: The system MUST default to **manual-trigger** deploys (a git change
  does not force a deploy) and MUST support optional **per-stack** webhook
  auto-deploy.
- **FR-008**: The control plane's own state MUST persist on the Dell (per the
  "stateful → Dell" rule) so it survives restarts.
- **FR-009**: The control plane's admin UI/API MUST be reachable only over the
  LAN/personal VPN, never publicly exposed (public domain + TLS is Phase 3).
- **FR-010**: Each node MUST be independently manageable — one node being down
  MUST NOT block managing or deploying to the other.
- **FR-011**: The system MUST allow adding a new node (install agent + add its git
  server definition) and removing a node (reassign its stacks) **without
  re-architecting** the fleet.
- **FR-012**: Standing up the orchestration (control plane + agents + git sync)
  MUST be reproducible from the repo following documented steps, consistent with
  the project's reproducibility north star.

### Key Entities

- **Control Plane**: the central management service on the Dell (web UI + API);
  the single origin of deploy actions and fleet status. Stateful.
- **Node Agent**: the per-node agent that executes deploys locally on behalf of
  the control plane; one on each node.
- **Server**: a declared node the control plane manages (`ragnaforge-dell`,
  `ragnaforge-mac`), including which node an agent runs on.
- **Stack**: a named Docker Compose project mapped to a directory (under
  `stacks/`) and a **target server**; the unit that gets deployed.
- **Resource Sync Definition**: the git-tracked declarations (under `komodo/`) the
  control plane reconciles against — the fleet's desired state.
- **Secret / Variable**: a named value injected from the `mise`-rendered
  environment and **referenced** (never stored) in git.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From the control plane alone, the operator deploys a test stack to a
  chosen node and its container runs — with **zero** manual SSH or `docker
  compose` on the node.
- **SC-002**: The servers and stacks the control plane manages are **exactly**
  those declared in git; a committed change is reflected after a sync.
- **SC-003**: **Zero** real secret values appear in any tracked file, yet a
  deployed stack still receives its secrets from the `mise`-rendered environment.
- **SC-004**: With manual mode (webhooks off), a git change does **not**
  auto-deploy; a manual trigger converges the stack.
- **SC-005**: Both nodes appear as healthy managed servers, and deploying to one
  node succeeds while the other node is offline.
- **SC-006**: The control plane's state (servers, stacks, history, config)
  survives a restart of the Dell — no re-setup required.
- **SC-007**: A competent operator can stand up the orchestration from the
  repository following documented steps, with secrets supplied via `.mise.toml`
  and no undocumented manual steps.
- **SC-008**: Adding or removing a node is a config + agent change (no
  re-architecture): the fleet reflects the change after a sync.

## Assumptions

- **Komodo is the settled orchestrator** and **Docker Compose** the stack format,
  per the master plan — fixed architectural facts, not open choices (as in earlier
  phases, requirements stay outcome-focused while the plan's chosen tool is named).
- **Phase 2 delivers the orchestration capability**, validated with a **minimal
  test stack** (a trivial stateless container). The real application stacks
  (Traefik/edge, media, apps) arrive in Phases 3–6 and are out of scope here.
- **Komodo Core runs on the Dell** (stateful → Dell) and is reached over
  LAN/Tailscale on a port; a public domain and TLS via Traefik are **Phase 3**.
- The control plane requires a **backing datastore on the Dell** (its persistence
  lives on the Dell); the exact store is a planning detail.
- **Secrets follow the Phase 0/1 `mise` pattern**: real values only in the
  gitignored `.mise.toml`; `.mise.toml.example` ships placeholders.
- Both nodes are the **Phase 1 "ready Docker hosts"** (Docker + compose plugin,
  reachable over SSH/LAN/Tailscale, admin/SSH baseline applied).
- The Phase 0 `komodo/` scaffolding (`servers.toml`/`stacks.toml` placeholders)
  and `stacks/` directory exist to be filled in.
- **Out of scope**: reverse proxy/TLS/domain (Phase 3), the application stacks
  (Phases 5–6), monitoring (Phase 8), and backups (Phase 9).

## Dependencies

- **Phase 1 complete**: two ready Docker hosts (`ragnaforge-dell`,
  `ragnaforge-mac`) reachable over the LAN and Tailscale, Docker Engine + compose
  plugin installed.
- **Phase 0 secret pattern** in place: `.mise.toml` (gitignored) + `.mise.toml.example`.
- The operator can reach both nodes over SSH/LAN/Tailscale to install agents.
