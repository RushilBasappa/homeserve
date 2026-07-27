# Runbook — basic-memory (self-hosted MCP knowledge-graph server)

A single **Dell-only**, **LAN/VPN-only** stack. Basic Memory is **not a web app** — it's an
[MCP](https://modelcontextprotocol.io) server that gives AI assistants (Claude Code / Claude
Desktop, and potentially the hermit agent) a persistent, human-readable memory: plain **Markdown**
notes forming a knowledge graph (wikilinks + observations), indexed in **SQLite** for search.

Upstream: <https://github.com/basicmachines-co/basic-memory> · Operating the fleet: [[homeserve-ops-access]].

> This is an **added app** riding the existing platform (edge/DNS/TLS/Komodo), **not** a formal
> PLAN phase (cf. wger, resume).

---

## ⚠ Security posture — read first

Basic Memory's HTTP endpoints have **NO authorization** (upstream is explicit: *"should not be
exposed on a public network"*). The **only** guard is the edge posture: the stack publishes **no
host ports** and is reachable **only** through Traefik on the LAN/tailnet — **never**
router-forwarded. **The tailnet is the trust boundary**: anyone on it can read/write the whole
knowledge graph. That's the same model as the lab's other unauthenticated internal tools
(AdGuard admin, etc.). Do **not** add a public DNS record or a router forward for
`memory.ragnaforge.xyz`.

---

## Prerequisites

- Phase-3 edge live (Traefik + wildcard TLS + AdGuard); `memory.ragnaforge.xyz` → the Dell
  (wildcard `*.ragnaforge.xyz` already resolves — no new DNS record).
- `komodo/stacks.toml` has the `basic-memory` `[[stack]]` (server `ragnaforge-dell`); `RunSync` applied.
- **No secrets** — nothing in `.mise.toml` / Periphery / `.env`.

**Verify at deploy** (image-tag discipline): confirm the pinned
`ghcr.io/basicmachines-co/basic-memory:<tag>` in `stacks/basic-memory/compose.yaml` is current.
Tags are **unprefixed** (`0.22.1`, not `v0.22.1`); at authoring time `0.22.1` == the `:latest`
digest. Releases: <https://github.com/basicmachines-co/basic-memory/releases>.

---

## Bring-up order

1. Declare the stack in `komodo/stacks.toml`, push, `RunSync` (or wait ≤5 min for the git poll).
2. **Deploy `basic-memory` (cold)** via Komodo (`DeployStack`). One container; it initialises the
   default project (`main` → `/app/data/basic-memory`) and the SQLite index on first boot.
3. **First-run permissions gotcha (watch for it):** the container runs non-root (appuser 1000).
   If a fresh named volume mounts root-owned, boot fails with a write/permission error in
   `docker logs basic-memory`. Fix: `docker run --rm -v basic-memory_basic-memory-data:/d -v basic-memory_basic-memory-config:/c alpine chown -R 1000:1000 /d /c` (rushil is in the `docker` group, no sudo), then `DeployStack` again.
4. **Smoke test the MCP endpoint** (behind the proxy):
   `curl -sI https://memory.ragnaforge.xyz/mcp` should connect with valid TLS (a bare GET may
   return 4xx/406 — that's the MCP handler rejecting a non-MCP request, which still proves it's up).

---

## Wiring a client (Claude Code)

The server speaks **streamable-http** at `https://memory.ragnaforge.xyz/mcp`. From a machine on
the LAN/tailnet:

```bash
claude mcp add --transport http basic-memory https://memory.ragnaforge.xyz/mcp
```

(Claude Desktop, which wants stdio, needs an `mcp-proxy` shim — see upstream `docs/Docker.md`.)
If a client can't speak streamable-http, switch the compose `command` to `--transport sse` (endpoint
becomes `/sse`) and recreate the stack.

**Note:** this is a **central, shared** memory over the tailnet — every wired client reads/writes the
same graph. That's the intended homeserve model (state lives on the Dell), vs. a per-machine local
`uvx basic-memory` install where the notes live beside each client.

---

## Audits (the invariants)

- **No public exposure**: `docker ps` on the Dell shows **no** published host ports for
  `basic-memory`; **no** router forward targets it. From off-LAN/off-VPN, `memory.ragnaforge.xyz`
  does not serve.
- **TLS behind proxy**: Let's Encrypt wildcard cert; `memory.ragnaforge.xyz/mcp` reachable over HTTPS.
- **No secrets in git**: nothing to leak — SQLite, no keys (this app adds zero mise vars).
- **Golden rule**: `docker volume ls` shows `basic-memory_basic-memory-data` and
  `basic-memory_basic-memory-config` on the **Dell**; **0** state on the Mac or under `/srv/nfs`.

---

## Backups gap (Phase 10)

This runbook stands the server up only. `basic-memory-data` (the entire Markdown knowledge graph)
is the irreplaceable state — `basic-memory-config` (SQLite index) is derived and rebuildable via
`basic-memory reindex`. The data volume is a **Phase-10 backup candidate**. Because the notes are
plain Markdown, they're also trivially portable/greppable outside the app — a nice property for the
[[homeserve-portability-goal]].
