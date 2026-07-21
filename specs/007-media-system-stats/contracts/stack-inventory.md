# Contract: Stack Inventory (stacks × node × ports × volumes × secrets)

The interface this phase adds to the fleet. Komodo declares each stack in `komodo/stacks.toml`;
every HTTP **UI** is reached at `https://<name>.ragnaforge.xyz` via Traefik (no host ports unless
noted). Stateful config lives in **Dell-local named volumes** (golden rule); nothing on `/srv/nfs`.

## Stacks

| Stack (name) | Compose file | Node | Services | Subdomain | Config volume | Notes |
|---|---|---|---|---|---|---|
| `tautulli` | `stacks/tautulli/compose.yaml` | Dell | tautulli | `tautulli` | `tautulli-config` | Plex watch stats; read-only via `PLEX_TOKEN` |
| `beszel` | `stacks/beszel/compose.yaml` | Dell | beszel (hub) | `beszel` | `beszel-data` | hub UI 8090; imports systems from `config.yml` |
| `beszel-agent-dell` | `stacks/beszel/agent.compose.yaml` | Dell | beszel-agent | — | — | generic agent; reads host + `docker.sock` |
| `beszel-agent-mac` | `stacks/beszel/agent.compose.yaml` | **Mac** | beszel-agent | — | — | **same generic file**; polled at `10.0.0.71:45876` |

- **The agent is ONE generic, node-agnostic file** (`stacks/beszel/agent.compose.yaml`). Each node
  gets a `beszel-agent-<node>` Komodo stack pointing at that **same** file, differing only by
  `server`. **Adding a node = one more `[[stack]]` block + one line in `config.yml` — never a new
  file.** (`ragnaforge-mac` is Apple hardware on Debian Linux — "mac" is the node name, not an OS.)
- **The hub is a single-purpose stack** (hub only); the Dell's own agent is `beszel-agent-dell`,
  the same generic stack as every other node — uniform, no special-cased bundling.
- Agents have no UI and no volume (stateless); no Traefik route. Deploy a node's agent when that
  node is awake (Periphery Ok).

## Ports

| Port | Proto | Stack | Exposure | Why |
|---|---|---|---|---|
| (none new published for HTTP) | — | tautulli, beszel hub | via Traefik only | "no host ports for HTTP" rule holds |
| 8181 | TCP | tautulli | internal (Traefik → 8181) | Tautulli UI/API |
| 8090 | TCP | beszel hub | internal (Traefik → 8090) | hub UI |
| 45876 | TCP | beszel agents | **LAN only** (hub → agent) | agent metrics port; not router-forwarded, not public |

The Beszel agent port is reachable **only on the LAN** (hub → agent). No inbound router forward
is added — these are not public services.

## Secrets (`.mise.toml.example` placeholders — real values only in gitignored `.mise.toml`)

| Var | Used by | Notes |
|---|---|---|
| `PLEX_TOKEN` | tautulli (Plex link), tautulli `configure/`; **already used by maintainerr** | **Reused** Plex server token — add the missing placeholder to `.mise.toml.example` this phase (currently only in the live file). Read-only. |
| `TAUTULLI_API_KEY` | tautulli (`config.ini`), homepage Tautulli widget, tautulli `configure/` | Deterministic (`openssl rand -hex 16`) so the Homepage widget + assert-play read a known key. |
| `BESZEL_KEY` | beszel agents (`KEY` env) | Hub **public** key — non-secret; MAY instead live in `komodo/variables.toml`. Agents accept only this hub. |
| `BESZEL_ADMIN_EMAIL` / `BESZEL_ADMIN_PASSWORD` | beszel hub | One-time superuser provisioning for the hub UI (SC-009 permits one-time creds). |

Secrets are forwarded to the Periphery env via `komodo/bootstrap/periphery.compose.yaml`
`environment:` + `make sync-secrets` + a Periphery recreate (see [[homeserve-ops-access]]), then
referenced in compose as `${VAR}`.

## Non-secret variables (`komodo/variables.toml`, `[[VAR]]` interpolation)

| Var | Value | Use |
|---|---|---|
| `DELL_LAN_IP` | 10.0.0.70 | existing — Dell agent / hub host |
| `MAC_LAN_IP` | 10.0.0.71 | existing — Mac agent host in `config.yml` |
| `FLEET_DOMAIN` | ragnaforge.xyz | existing — hostnames |
| (optional) Plex host/port, agent port, `BESZEL_KEY` | — | add if kept out of secrets |

## Komodo declaration (`komodo/stacks.toml`)

Four `[[stack]]` entries, all `webhook_enabled = false` (manual deploys), tagged `phase-6` /
`stats`:

- `tautulli` → `server = "ragnaforge-dell"`, `file_paths = ["stacks/tautulli/compose.yaml"]`
- `beszel` → `server = "ragnaforge-dell"`, `file_paths = ["stacks/beszel/compose.yaml"]`
- `beszel-agent-dell` → `server = "ragnaforge-dell"`, `file_paths = ["stacks/beszel/agent.compose.yaml"]`
- `beszel-agent-mac` → `server = "ragnaforge-mac"`, `file_paths = ["stacks/beszel/agent.compose.yaml"]`

The two agent stacks share the **same** `file_paths` — the generic agent. A third node would add
`beszel-agent-<node>` with that same path and its own `server`.

## Traefik routing (per UI, canonical labels)

Each Dell-hosted UI carries the canonical label set (as every Phase-3/5 app does):

```yaml
- "traefik.enable=true"
- "traefik.http.routers.<name>.rule=Host(`<name>.ragnaforge.xyz`)"
- "traefik.http.routers.<name>.entrypoints=websecure"
- "traefik.http.routers.<name>.tls=true"
- "traefik.http.services.<name>.loadbalancer.server.port=<8181|8090>"
```

The **Mac agent has no router** (no UI). HTTP→HTTPS redirect and the wildcard cert come from the
Phase-3 edge unchanged (FR-012, SC-008).
