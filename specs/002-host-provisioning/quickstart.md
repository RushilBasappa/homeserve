# Quickstart & Validation: Phase 1 — Migration & Host Provisioning

Validates that the reusable provisioning works and that the one-time migration
runbook is complete. The two are validated separately, matching the spec's
separation of concerns.

## Prerequisites

- Phase 0 scaffolding present; `mise` installed with a filled-in `.mise.toml`
  (at least `TAILSCALE_AUTHKEY`).
- Ansible installed on the control machine. The playbook's collections
  (`ansible.posix`) are installed by `make deps`, which the `provision` targets
  run automatically — no separate `ansible-galaxy` step needed.
- For provisioning: at least one **freshly installed Debian 12** node reachable
  over SSH with the operator's key authorized.

## Setup

```sh
cd homeserve                      # repo root
cp .mise.toml.example .mise.toml  # if not already done — fill in TAILSCALE_AUTHKEY
```

## Validation scenarios

### 1. Provision a fresh node with one command (User Story 2 / SC-002)

```sh
make provision-dell               # or `make provision` for both
```

**Expected**: the run completes with no manual follow-up. See the postconditions
in [contracts/provisioning-contract.md](./contracts/provisioning-contract.md).

### 2. Idempotency (User Story 2 / SC-003)

```sh
make provision-dell               # run again immediately
```

**Expected**: the Ansible recap shows `changed=0` — the node was already in the
desired state.

### 3. Ready Docker host checks (SC-004, SC-005, FR-009..FR-012, FR-017)

Run on/against each node (see the contract for the full list):

```sh
docker run --rm hello-world                       # Docker works
sysctl -n net.ipv4.ip_forward                     # -> 1 on the Dell
sshd -T | grep -Ei 'passwordauthentication|permitrootlogin'   # both 'no'
tailscale status                                  # node online
```

**Expected**: all pass. For NFS, from the Mac:

```sh
touch /srv/nfs/.probe && rm /srv/nfs/.probe && echo "NFS rw OK"
```

### 4. Automation is migration-free (SC-008 / FR-016)

```sh
grep -rIEi 'k3s|preserve|snapshot|restore|reinstall|teardown' provision/ Makefile \
  && echo "FAIL: migration logic in automation" || echo "OK: automation is migration-free"
```

**Expected**: `OK: automation is migration-free` (no matches).

### 5. Both nodes reachable over Tailscale (User Story 4 / SC-007)

```sh
tailscale status | grep -E 'ragnaforge-(dell|mac)'
```

**Expected**: both nodes appear online.

### 6. One-time migration runbook is complete (User Story 1 & 3 / SC-001, SC-006)

```sh
f=docs/runbooks/phase1-migration.md
for kw in preserve verify restore reinstall "make provision"; do
  grep -qi "$kw" "$f" || echo "runbook missing step: $kw"
done
```

**Expected**: no output. Then review that a verification **gate precedes** the
reinstall step. Full requirements in
[contracts/migration-runbook-contract.md](./contracts/migration-runbook-contract.md).

## Done when

- Scenarios 1–3 pass: a fresh node reaches the ready Docker host state with one
  command, idempotently.
- Scenario 4 confirms no one-time logic leaked into the automation.
- Scenario 5 confirms Tailscale reachability.
- Scenario 6 confirms the migration runbook documents every step in the right
  order.

Mapping of scenarios → requirements lives in [data-model.md](./data-model.md);
implementation steps are produced by `/speckit-tasks` into `tasks.md`.
