# `stacks/` — Docker Compose stacks

**One directory per Compose stack.** Every application (or tightly-coupled group
of services) lives in its own subdirectory here, named after the app.

```text
stacks/
├── traefik/          # reverse proxy + TLS
│   ├── compose.yaml
│   └── ...
├── jellyfin/
│   └── compose.yaml
└── <app>/
    └── compose.yaml
```

## Conventions

- **One stack = one directory.** The directory name is the stack name (see
  [naming](../docs/CONVENTIONS.md#naming)).
- Each directory holds a `compose.yaml` plus any stack-specific config
  (Traefik dynamic files, app config templates, etc.).
- **No real secrets here.** Reference variables rendered from `mise`
  (`${CLOUDFLARE_API_TOKEN}`) — never literal credentials. See the
  [secrets pattern](../.mise.toml.example).
- **Stateful data → the Dell** (local volume or NFS), per the "golden rule" in
  [`docs/CONVENTIONS.md`](../docs/CONVENTIONS.md#data-placement). The Mac runs
  stateless stacks only.

This layout maps directly onto Komodo Resource Sync (Phase 2): each directory
becomes a declared Stack that Komodo deploys on demand.

Currently empty — stacks are added starting in Phase 3 (edge/TLS) onward.
See the [new-app checklist](../docs/CONVENTIONS.md#new-app-checklist) to add one.
