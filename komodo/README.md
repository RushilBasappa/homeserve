# `komodo/` — Komodo resource-sync definitions

Declarations that **Komodo** reads via [Resource
Sync](https://komo.do/docs/sync-resources): the Servers (nodes) and Stacks that
make up the fleet. This directory is the git-synced source of truth Komodo
reconciles against.

## What lives here (from Phase 2)

- **Servers** — the nodes running Komodo Periphery (`ragnaforge-dell`,
  `ragnaforge-mac`).
- **Stacks** — each maps a name to a directory under [`../stacks/`](../stacks/)
  and the server it deploys to.
- **Variables / secrets** — references injected from `mise`-rendered env (never
  literal values here).

```text
komodo/
├── servers.toml      # node definitions
├── stacks.toml       # stack → directory → server mappings
└── ...
```

## Deploy model

The git repo is storage + history, **not** a forced deploy button. Komodo syncs
from this directory; you deploy on a **manual trigger** (UI/CLI), or opt into a
per-stack webhook for auto-deploy. See the git-workflow note in
[`../PLAN.md`](../PLAN.md#3-design-principles-the-answers-to-recurring-questions).

Currently empty — populated in **Phase 2 (Orchestration)**.
