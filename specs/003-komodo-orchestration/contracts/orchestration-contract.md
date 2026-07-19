# Contract: Central Orchestration (Komodo)

The interface and guarantees the operator (and later phases) rely on. The fleet
conforms if and only if all of the following hold.

## Interface

| Surface | Effect |
|---|---|
| Komodo Core web UI / API (`http://<dell>:9120`) | View servers/stacks/status/logs; trigger deploys |
| `make komodo-core` (or documented `mise exec -- docker compose ...`) | Bootstrap Core + MongoDB on the Dell |
| `make komodo-periphery` (per node) | Bootstrap the Periphery agent on a node |
| ResourceSync (from `komodo/*.toml`) | Reconcile declared Servers/Stacks; deploy on confirm |
| Per-stack webhook (optional) | Auto-deploy that stack on git push |

Bootstrap wraps `mise exec -- docker compose ...`, so Core's secrets come from the
gitignored `.mise.toml`.

## Starting-state precondition

- Both nodes are **Phase-1 ready Docker hosts** (Docker + compose plugin,
  reachable over LAN/Tailscale, admin user in the `docker` group). (FR-002)

## Definition of "managed fleet" (postconditions)

After bring-up and an initial sync:

1. **Central control** — Komodo Core is reachable on the LAN/Tailscale at `:9120`
   and **not** publicly; a single admin user exists. (FR-001, FR-009)
2. **Both agents healthy** — Periphery on `ragnaforge-dell` and `ragnaforge-mac`
   both register and report healthy to Core. (FR-002)
3. **Git-declared** — the managed Servers and Stacks are exactly those declared in
   `komodo/*.toml`; a committed change is reflected after a sync. (FR-003, SC-002)
4. **Deploy from one place** — the `whoami` test stack deploys to a **chosen** node
   from Core alone (UI or CLI), its container runs there, and its status + logs are
   visible centrally — with **no** SSH/`docker compose` on the node. (FR-004,
   FR-005, SC-001)
5. **Secrets from mise** — a stack consuming a secret receives it from the
   `mise`-rendered environment; **no** real secret value appears in any tracked
   file. (FR-006, SC-003)
6. **Deliberate deploys** — with webhooks off, a git change does **not**
   auto-deploy; a manual trigger converges the stack. (FR-007, SC-004)
7. **State persists** — after a Dell restart, Core's servers/stacks/history/config
   are intact with no re-setup. (FR-008, SC-006)

## Invariants

- **Independent nodes** — deploying to one node succeeds while the other is
  offline. (FR-010, SC-005)
- **Add/remove without re-architecture** — a node is added (agent + `[[server]]`)
  or removed (reassign its stacks) as a config change. (FR-011, SC-008)
- **Secret-free tree** — no real secret value is tracked; references only.
- **Pinned, not `:latest`** — Komodo/DB images pinned to a visible major.

## Conformance checks (scriptable)

```sh
# Core reachable on the LAN, not public (run on the LAN/Tailscale):
curl -fsS http://10.0.0.70:9120/ >/dev/null && echo "Core up"

# Both servers healthy + test stack deployed to a chosen node — verify in the UI,
# or via the Komodo CLI/API listing servers and the whoami stack's state.

# whoami actually runs on the target node (e.g. the Mac), NOT the other:
ssh ragnaforge-mac  'docker ps --format "{{.Names}}" | grep -q whoami && echo "on mac"'
ssh ragnaforge-dell 'docker ps --format "{{.Names}}" | grep -q whoami || echo "not on dell"'

# Secret-free tree (expect NO matches of real values; references like ${VAR}/[[VAR]] are fine):
grep -rIEi 'changeme-|-----BEGIN|tskey-[0-9]' komodo/ stacks/ && echo "FAIL: secret in tree" || echo "OK: secret-free"

# Idempotent/deliberate: a sync with no git change proposes no actions.
```

Any failed check — Core publicly reachable, an unhealthy agent, a stack that
deployed to the wrong node, a real secret in the tree, or an auto-deploy with
webhooks off — indicates non-conformance.
