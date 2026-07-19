# Quickstart & Validation: Phase 2 — Orchestration (Komodo)

Validates that the two Phase-1 Docker hosts become a **centrally managed fleet**:
Core up, both agents healthy, git-declared resources, deploy from one place,
secrets from `mise`, deliberate deploys, node independence, and state persistence.

## Prerequisites

- **Phase 1 complete**: both nodes are ready Docker hosts (Docker + compose
  plugin) reachable over LAN/Tailscale.
- `mise` with a filled-in `.mise.toml` (Komodo entries: `KOMODO_DB_PASSWORD`,
  `KOMODO_WEBHOOK_SECRET`, `KOMODO_JWT_SECRET`).
- This repo checked out on the Dell (or reachable by Komodo to pull).

## Setup

```sh
cd homeserve
cp .mise.toml.example .mise.toml   # if not already — fill in the KOMODO_* values
mise trust                         # so mise renders [env]
```

## Validation scenarios

### 1. Bootstrap the control plane (FR-001, FR-008)

```sh
make komodo-core         # on the Dell: komodo-core:2 + mongo (secrets via mise)
```

**Expected**: Core's web UI answers on `http://10.0.0.70:9120`; create the single
admin user, then disable open registration. See
[contracts/orchestration-contract.md](./contracts/orchestration-contract.md).

### 2. Connect both agents (FR-002, FR-010)

```sh
make komodo-periphery    # run on/against each node (dell + mac)
```

**Expected**: after declaring the Servers (scenario 3), both
`ragnaforge-dell` and `ragnaforge-mac` show **healthy** in Core.

### 3. Sync the fleet from git (FR-003, SC-002)

Commit `komodo/servers.toml`, `komodo/stacks.toml`, then run the ResourceSync in
Core.

**Expected**: exactly the declared Servers and the `whoami` Stack appear; the sync
shows a **diff** and applies on confirmation (not automatically). Change a value in
git, re-sync → the change is reflected.

### 4. Deploy a stack to a chosen node from Core alone (US1 / SC-001)

Deploy `whoami` targeting the **Mac** from the Core UI/CLI — no SSH.

```sh
# verify placement — runs on the Mac, not the Dell:
ssh ragnaforge-mac  'docker ps --format "{{.Names}}" | grep whoami'
ssh ragnaforge-dell 'docker ps --format "{{.Names}}" | grep whoami || echo "not on dell"'
```

**Expected**: the container runs on the Mac; its status + logs are visible in Core.

### 5. Secret injection with nothing in git (US3 / SC-003)

Give `whoami` an env var sourced from a `mise` secret (e.g. a dummy token) via
`${VAR}`; deploy.

```sh
# no real secret value anywhere in the tree (references are fine):
grep -rIEi 'changeme-|-----BEGIN|tskey-[0-9]' komodo/ stacks/ \
  && echo "FAIL: secret in tree" || echo "OK: secret-free"
```

**Expected**: the value reaches the container from the `mise`-rendered
environment; the `grep` finds no real value. **Bench-check** (per research R4):
confirm the Periphery-run compose resolves `${VAR}`; if not, use the Komodo
secret-Variable `[[VAR]]` fallback.

### 6. Deliberate deploys (FR-007 / SC-004)

With webhooks off, commit a change to `stacks/whoami/compose.yaml` and do nothing.

**Expected**: the running stack is unchanged until a manual sync/deploy. Then
enable the per-stack webhook and confirm a push auto-deploys that stack.

### 7. Node independence (FR-010 / SC-005)

Stop Periphery on the Mac (or power it off); deploy/redeploy a stack to the Dell.

**Expected**: the Dell deploy succeeds; the Mac is reported offline, not silently
treated as done.

### 8. State survives a restart (FR-008 / SC-006)

Reboot the Dell.

**Expected**: Core comes back with servers, stacks, history, and config intact —
no re-setup; both agents reconnect.

## Done when

- Scenarios 1–4: Core up, both agents healthy, git-declared, and a stack deploys
  to a chosen node from Core alone.
- Scenario 5: a secret reaches a stack with no value in the tree.
- Scenario 6: deploys are manual by default; per-stack webhook works.
- Scenarios 7–8: nodes are independent and Core state persists.

Requirement mapping lives in [data-model.md](./data-model.md); the interface and
postconditions in [contracts/](./contracts/). Implementation steps are produced by
`/speckit-tasks` into `tasks.md`.
