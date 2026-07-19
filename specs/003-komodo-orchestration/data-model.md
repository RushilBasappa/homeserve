# Phase 2 Data Model: Orchestration (Komodo)

No application data store. The "entities" are the orchestration artifacts and the
resources Komodo manages, each mapped to the functional requirements in `spec.md`.

## Entity: Control Plane (Komodo Core)

The central UI/API on the Dell — the single origin of deploy actions and status.

| Field | Value / required content | Source FR |
|---|---|---|
| Deployment | Compose stack on the Dell: `komodo-core:2` + MongoDB (cache-capped) | FR-001, FR-008 |
| Interface | Web UI **and** API/CLI on port `9120` | FR-001 |
| Exposure | LAN/Tailscale only — no router forward, no public DNS | FR-009 |
| Auth | Local admin user; open registration disabled after first user | FR-009 |
| State | MongoDB named volume on the Dell (servers, stacks, history, config) | FR-008 |
| Secrets | DB password, JWT/webhook secrets from `.mise.toml` via `mise exec` | FR-006 |

**Validation rules**:
- Core MUST persist its state across a Dell restart (no re-setup). (FR-008, SC-006)
- Core's admin surface MUST NOT be reachable from the public internet. (FR-009)
- No real secret value for Core may appear in any tracked file. (FR-006)

## Entity: Node Agent (Komodo Periphery)

The per-node agent that executes deploys locally; one on each node.

| Field | Required content | Source FR |
|---|---|---|
| Deployment | `komodo-periphery:2` container per node; mounts `/var/run/docker.sock` | FR-002 |
| Address | Reachable by Core inbound at `http://10.0.0.7x:8120` | FR-002 |
| Auth | PKI (Ed25519) handshake with Core (v2) | FR-002 |
| Placement | One on `ragnaforge-dell`, one on `ragnaforge-mac` | FR-002, FR-010 |

**Validation rules**:
- Both agents MUST register and report healthy to Core. (FR-002)
- One agent being down MUST NOT block deploying via the other. (FR-010, SC-005)

## Entity: Server (declared)

A node the control plane manages, declared in git.

| Field | Required content | Source FR |
|---|---|---|
| `servers.toml` | `[[server]]` for `ragnaforge-dell` and `ragnaforge-mac` | FR-003 |
| `address` | The node's Periphery endpoint (`http://10.0.0.7x:8120`) | FR-002, FR-003 |
| `enabled` | Node is an active deploy target | FR-010 |

**Validation rules**:
- The managed servers MUST be exactly those declared in git. (FR-003, SC-002)
- Adding/removing a server is a git + agent change (no re-architecture). (FR-011, SC-008)

## Entity: Stack (declared)

A named Compose project mapped to a directory and a target server — the unit that
gets deployed.

| Field | Required content | Source FR |
|---|---|---|
| `stacks.toml` | `[[stack]]` mapping name → `stack.config.server` → `file_paths` | FR-003, FR-004 |
| Compose source | `stacks/<app>/compose.yaml` in this repo (Komodo pulls the repo) | FR-004 |
| Target | A specific declared Server (dell or mac) | FR-004 |
| Deploy mode | Manual by default; optional per-stack webhook | FR-007 |
| Phase-2 instance | `whoami` (trivial stateless) deployed to each node | (validation) |

**Validation rules**:
- A stack MUST deploy to its declared node from Core alone — no SSH/compose on the
  node. (FR-004, SC-001)
- A stack's status/health and logs MUST be visible centrally. (FR-005)
- A stack referencing a missing directory/secret MUST fail clearly, not silently. (edge case)

## Entity: Resource Sync Definition

The git-tracked TOML the control plane reconciles against — the fleet's desired
state.

| Field | Required content | Source FR |
|---|---|---|
| Location | `komodo/*.toml` in this repo, read by a Komodo ResourceSync | FR-003 |
| Content | Servers, Stacks, and **non-secret** Variables only | FR-003, FR-006 |
| Reconcile | Komodo diffs vs live state; applies on confirmation (manual) | FR-007 |

**Validation rules**:
- Git MUST be the source of truth; a committed change appears after a sync. (FR-003, SC-002)
- No real secret value may appear in any synced file. (FR-006, SC-003)

## Entity: Variable / Secret

A named value consumed by a stack, referenced (never stored) in git.

| Field | Required content | Source FR |
|---|---|---|
| Non-secret vars | `variables.toml` (plain config) | FR-003 |
| Secret values | From `mise`-rendered env → `${VAR}` in compose (primary), or Komodo secret Variable `[[VAR]]` (fallback) | FR-006 |
| Tracked form | Only the **name**/reference — never the value | FR-006 |

**Validation rules**:
- A deployed stack MUST receive its secret from the `mise`-rendered environment. (SC-003)
- A missing required secret MUST cause a clear deploy failure, not a blank value. (US3/AC3)
- `grep` over tracked files MUST find **zero** real secret values. (SC-003)
