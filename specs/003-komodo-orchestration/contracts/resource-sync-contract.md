# Contract: Git-Declared Resources (ResourceSync)

Defines what the git-synced Komodo resource definitions under `komodo/` MUST
contain and guarantee. Git is the **source of truth**; Komodo reconciles against
it.

## Required resources (in `komodo/*.toml`)

| # | Resource | Requirement |
|---|---|---|
| 1 | **Servers** | `[[server]]` for `ragnaforge-dell` and `ragnaforge-mac`, each with its Periphery `address` (`http://10.0.0.7x:8120`) and `enabled = true`. (FR-002, FR-003) |
| 2 | **Stacks** | `[[stack]]` for the `whoami` test stack, with `stack.config.server` set to a target node and `file_paths` pointing at `stacks/whoami/compose.yaml` in this repo. (FR-003, FR-004) |
| 3 | **Variables** | `variables.toml` holds **non-secret** config only. Secret values are never present — only `${VAR}` / `[[VAR]]` references. (FR-006) |

## Guarantees

- **Source of truth**: the Servers and Stacks Komodo manages are exactly those
  declared here; a committed change is reflected after a sync. (SC-002)
- **Secret-free**: no real secret value appears in any synced file — secret export
  is redacted, and values live only in the `mise`-rendered environment. (SC-003)
- **Deliberate**: a sync shows the computed diff and applies on confirmation;
  auto-deploy is opt-in per stack (webhook). (FR-007, SC-004)
- **Portable**: adding/removing a node or stack is a change to these files (+ the
  node's agent), not a re-architecture. (FR-011, SC-008)

## Conformance checks

```sh
# Every required resource is declared:
grep -q 'name *= *"ragnaforge-dell"' komodo/servers.toml || echo "missing: dell server"
grep -q 'name *= *"ragnaforge-mac"'  komodo/servers.toml || echo "missing: mac server"
grep -q 'whoami' komodo/stacks.toml                       || echo "missing: whoami stack"

# A stack targets a specific server and points at this repo's compose:
grep -q 'server *=' komodo/stacks.toml      || echo "stack has no target server"
grep -q 'stacks/whoami' komodo/stacks.toml  || echo "stack has no file_paths"

# No secret values in the synced tree (references are fine):
grep -rIEi 'changeme-|-----BEGIN|tskey-[0-9]|password *= *"[^$]' komodo/ \
  && echo "FAIL: secret value in komodo/" || echo "OK: secret-free"
```

Any missing resource, an untargeted stack, or a real secret value indicates
non-conformance.
