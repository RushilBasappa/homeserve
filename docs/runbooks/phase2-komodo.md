# Runbook: Phase 2 — Orchestration (Komodo)

**This is the one-time bring-up of the control plane.** It is followed by hand to
turn the two Phase-1 Docker hosts into a **centrally managed fleet**: Komodo Core
on the Dell, a Periphery agent on each node, git as the source of truth, secrets
from `mise`, and deliberate deploys. After this, everything above the control
plane (the `whoami` test stack and every later app) is deployed from Komodo
alone — no SSH, no manual `docker compose` on a node.

The reusable, repeatable path lives in the tracked config: `komodo/bootstrap/`
(the compose files), the `komodo-core` / `komodo-periphery` `make` targets, and
the git-declared resources under `komodo/`. The steps below are the human glue —
creating the admin user, wiring the ResourceSync, and validating.

> **Load-bearing guarantees:** deploy any stack from one place (SC-001), git is
> the source of truth (SC-002), and the tree stays secret-free (SC-003).

Steps are ordered. Follow them top to bottom.

---

## 0. Prerequisites

- **Phase 1 complete** — both nodes are ready Docker hosts (Docker + compose
  plugin, `rushil` in the `docker` group), reachable over LAN/Tailscale.
- **`.mise.toml` filled in** on **each node** with the Komodo secrets from
  `.mise.toml.example`: `KOMODO_DB_PASSWORD`, `KOMODO_WEBHOOK_SECRET`,
  `KOMODO_JWT_SECRET`, `KOMODO_PASSKEY`, `WHOAMI_TEST_SECRET`. `KOMODO_PASSKEY`
  **must be identical** on the Dell (Core) and every Periphery node.
- This repo checked out on each node.

```sh
cd homeserve
cp .mise.toml.example .mise.toml     # fill in the KOMODO_* values
mise trust                           # so mise renders [env]
```

Generate strong secrets, e.g. `openssl rand -hex 32` for each.

---

## 1. Bring up Komodo Core — the Dell only (FR-001, FR-008)

Core is bootstrapped **out-of-band** — it *is* the orchestrator, so it cannot be
deployed by a Komodo that isn't running yet (research R3).

```sh
# On the Dell:
cp komodo/bootstrap/core.env.example komodo/bootstrap/core.env   # non-secret config
make komodo-core
```

`make komodo-core` wraps `mise exec -- docker compose`, so Core's secrets are
rendered from `.mise.toml` into the environment — never a tracked file.

**Verify:** Core's UI answers on the LAN/Tailscale:

```sh
curl -fsS http://10.0.0.70:9120/ >/dev/null && echo "Core up"
```

Core is published on `:9120` but the router forwards no port to it → LAN and
Tailscale can reach it, the public internet cannot (FR-009). Public domain + TLS
is Phase 3.

---

## 2. Create the single admin, disable registration (FR-009)

1. Open `http://10.0.0.70:9120` and register the **first** user — this is the
   single admin.
2. Confirm open registration is **off** so no one else can self-register. The
   bootstrap ships `KOMODO_DISABLE_USER_REGISTRATION=true` in `core.env`; if the
   very first registration is blocked, flip it to `false` for that one bring-up,
   register, then set it back to `true` and `make komodo-core` again to redeploy.

---

## 3. Bring up Periphery on each node (FR-002, FR-010)

```sh
# On the Dell AND on the Mac:
make komodo-periphery
```

Each agent listens on `:8120`; Core connects inbound to it. The shared
`KOMODO_PASSKEY` authenticates the connection.

---

## 4. Declare the fleet from git — ResourceSync (FR-003, SC-002)

The servers and stacks are declared in `komodo/*.toml`. Point Komodo at this repo
and sync.

1. **Sync repo.** `komodo/stacks.toml` already points at
   `RushilBasappa/homeserve` on GitHub (`branch = "main"`). Push this repo to that
   remote first so Komodo can pull it. If the repo is **private**, add a git
   account/token for `RushilBasappa` in Core (Settings → Git Accounts). If you'd
   rather not pull from a remote, clone the repo onto each node and convert the
   stack to files-on-host (research R5).
2. **Create a ResourceSync in Core** pointing at the repo's `komodo/` directory
   (Settings → Resource Syncs → New). Run the initial sync.
3. **Confirm the diff and apply.** The sync shows exactly the declared Servers
   (`ragnaforge-dell`, `ragnaforge-mac`) and the `whoami` Stack. Apply on
   confirmation — nothing deploys automatically.

**Verify:** both servers show **healthy** in Core.

> Managed == declared: the servers/stacks Komodo manages are exactly those in
> `komodo/`. To prove git is the source of truth (US2), change a declared value
> (e.g. retarget `whoami` in `stacks.toml`, or a value in `variables.toml`),
> commit, re-sync — Core's diff reflects it and applies on confirmation.

---

## 5. Deploy the test stack to a chosen node (US1, SC-001)

From the Core UI (or CLI/API), deploy `whoami`. It targets `ragnaforge-mac` in
`stacks.toml`.

**Verify placement — on the Mac, not the Dell:**

```sh
ssh ragnaforge-mac  'docker ps --format "{{.Names}}" | grep -q whoami && echo "on mac"'
ssh ragnaforge-dell 'docker ps --format "{{.Names}}" | grep whoami || echo "not on dell"'
```

Its status and logs are visible centrally in Core — with no SSH or `docker
compose` on the node (that is the deliverable; the SSH above is only to *prove*
placement).

---

## 6. Secret injection with nothing in git (US3, SC-003)

`stacks/whoami/compose.yaml` references `${WHOAMI_TEST_SECRET}`; the value is set
only in each node's gitignored `.mise.toml`.

**Primary path (research R4):** `mise` renders `WHOAMI_TEST_SECRET` into the
Periphery process environment (see `periphery.compose.yaml`), and the
Periphery-run compose resolves `${WHOAMI_TEST_SECRET}`. Deploy, then confirm:

```sh
ssh ragnaforge-mac 'docker exec whoami env | grep WHOAMI_TEST_SECRET'
```

**Bench-check + fallback (the one open risk).** If the value does **not** reach
the container — i.e. Periphery does not forward its process env into the compose
it invokes — switch to the Komodo **secret-Variable `[[VAR]]`** path:

1. Create a Komodo Variable `WHOAMI_TEST_SECRET` with `is_secret = true`, seeding
   its value once from the mise-rendered env (it is redacted on export and in
   logs, so git stays secret-free).
2. Reference it in the compose as `[[WHOAMI_TEST_SECRET]]` instead of
   `${WHOAMI_TEST_SECRET}`.

**Record which path is in use** here once validated on the bench (this resolves
task T017). Either way, confirm the tree is secret-free:

```sh
grep -rIEi 'changeme-|-----BEGIN|tskey-[0-9]' komodo/ stacks/ \
  && echo "FAIL: secret in tree" || echo "OK: secret-free"
```

---

## 7. Deliberate deploys — manual default + optional webhook (US4, FR-007)

- **Manual default:** commit a change to `stacks/whoami/compose.yaml` and trigger
  nothing. The running stack stays unchanged until a manual sync/deploy.
- **Opt-in auto-deploy:** set `webhook_enabled = true` for `whoami` in
  `stacks.toml`, register the git webhook (signed with `KOMODO_WEBHOOK_SECRET`),
  and confirm a push auto-deploys **only** that stack. Other stacks stay manual.

---

## 8. Node independence & state persistence (SC-005, SC-006)

- **Independence:** stop Periphery on the Mac (or power it off) and deploy/redeploy
  a stack to the Dell. The Dell deploy succeeds; the Mac is reported offline, not
  silently treated as done.
- **Persistence:** reboot the Dell. Core comes back with servers, stacks, history,
  and config intact (its MongoDB lives in a named volume **on the Dell**) — no
  re-setup; both agents reconnect.

---

## 9. Add or remove a node later (FR-011, SC-008)

Adding or removing a node is a **config change**, not a re-architecture:

- **Add:** run `make komodo-periphery` on the new node, add a `[[server]]` block
  to `komodo/servers.toml` (its `http://<ip>:8120` address, `enabled = true`),
  commit, and re-sync. Point stacks at it as desired.
- **Remove:** reassign its stacks to another server in `stacks.toml`, delete its
  `[[server]]` block, commit, re-sync, then stop its Periphery agent.

---

## Done when

- Core is up on the LAN/Tailscale (not public), single admin exists, registration
  disabled.
- Both agents register and report healthy; the fleet matches `komodo/*.toml`.
- `whoami` deploys to a chosen node from Core alone, status + logs visible
  centrally.
- A secret reaches the stack with no value in the tree; the secret-free grep
  passes; the chosen secret path (`${VAR}` or `[[VAR]]`) is recorded above.
- Deploys are manual by default, per-stack webhook works, nodes are independent,
  and Core state survives a Dell reboot.

Contracts: [orchestration-contract.md](../../specs/003-komodo-orchestration/contracts/orchestration-contract.md),
[resource-sync-contract.md](../../specs/003-komodo-orchestration/contracts/resource-sync-contract.md).
Scenario list: [quickstart.md](../../specs/003-komodo-orchestration/quickstart.md).
