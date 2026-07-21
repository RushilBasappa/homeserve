# Phase 6 runbook — Media & System Stats (Tautulli + Beszel)

"See the audience and the load." Two low-footprint tools, dashboards only (no push — that's
Phase 9). Spec/plan: `specs/007-media-system-stats/`.

- **Tautulli** (Dell) — Plex watch stats: now-playing + **direct-play vs transcode** + per-user
  history. Read-only via the Plex **server** token. SQLite DB on the Dell.
- **Beszel** — hub (Dell) + agent (Dell) + agent (Mac): one fleet view (CPU/RAM/disk %/net/temps
  + per-container), configurable thresholds shown as **visible indicators**.

Operating the fleet: SSH/Komodo per the ops-access notes (Komodo API on the Dell `:9120`,
`~/.local/bin/mise`, `make sync-secrets`). Mac deploys need the Mac awake (Periphery Ok).

---

## 0. Golden rules for this phase

- **State → Dell.** Only `tautulli-config` and `beszel-data` hold state, both Dell-local named
  volumes. The Mac agent is **stateless**.
- **No `[[VAR]]` in git compose.** Komodo does not interpolate Komodo variables into git-pulled
  compose. Non-secret values (Plex host `http://plex:32400`, agent port `45876`, node IPs
  `10.0.0.70`/`10.0.0.71`, the Beszel public key when known) are **inlined as literals**; only
  true secrets are forwarded to the Periphery env and referenced as `${VAR}`.
- **Dashboards only.** Configure thresholds; wire **no** notification channel. Phase 9 adds push.

---

## 1. Secrets & forwarding (one-time)

Placeholders live in `.mise.toml.example`; real values in the gitignored `.mise.toml`.

| Var | Consumed by | Forwarded to Periphery? |
|---|---|---|
| `PLEX_TOKEN` | Tautulli **configure play** (runs on the workstation, like Maintainerr) | **No** — workstation-only, same as `MEDIA_ADMIN_*` |
| `TAUTULLI_API_KEY` | Tautulli first-run (deterministic api_key) + Homepage widget (container) | **Yes** (Homepage container needs it) |
| `BESZEL_KEY` | Beszel **agents** (`KEY=` env, on both nodes) | **Yes** (both Dell & Mac Periphery) |
| `BESZEL_ADMIN_EMAIL` / `BESZEL_ADMIN_PASSWORD` | Hub superuser (one-time UI/CLI provisioning) | **No** — one-time, not a container env |

Steps:

1. Fill the new values in `.mise.toml` (`PLEX_TOKEN` = the Plex **server** token — the same one
   Maintainerr uses; `TAUTULLI_API_KEY` = `openssl rand -hex 16`).
2. `BESZEL_KEY` is only known **after** the hub's first start (§4). Deploy the hub first, copy its
   public key, paste it into `.mise.toml`, then `make sync-secrets` again before deploying agents.
3. `make sync-secrets` + recreate Periphery (per ops-access) so `${TAUTULLI_API_KEY}` and
   `${BESZEL_KEY}` resolve on **both** nodes.

---

## 2. Declare & sync the stacks

`komodo/stacks.toml` has `tautulli`, `beszel` (hub), and one agent stack per node —
`beszel-agent-dell` + `beszel-agent-mac`, both pointing at the **same** generic
`stacks/beszel/agent.compose.yaml` — all `webhook_enabled = false`. Push, then Komodo `RunSync`
(or wait ≤5 min for the git poll).

## 3. Tautulli (US1)

1. `DeployStack tautulli`.
2. **One-time first-run** (permitted credential provisioning, SC-009): open
   `https://tautulli.ragnaforge.xyz`, complete the short wizard — sign in to Plex, select the
   server, and set the API key to your `TAUTULLI_API_KEY` value (Settings → Web Interface → API).
   Set history retention to a bounded window (FR-005). See `stacks/tautulli/configure/config.ini.example`
   for the exact keys if you prefer to seed the volume instead of clicking.
   - **⚠️ Use a MANUAL Plex connection, not auto-discovery.** The wizard's auto-discovery picks
     Plex's *published external URL* (`plex.ragnaforge.xyz:443`) and sets it as HTTP-on-a-TLS-port,
     so every stats poll hits the Traefik edge → `404`, "error communicating with your Plex
     Server", no stats. Fix: Settings → Plex Media Server → **Manual Connection** →
     IP/Host `plex`, Port `32400`, SSL **off** (both containers share the `traefik` network, so
     `http://plex:32400` is the correct edge-free path). config.ini ends up:
     `pms_ip = plex`, `pms_port = 32400`, `pms_ssl = 0`, `pms_url = http://plex:32400`,
     `pms_url_manual = 1`. (This is what `configure/config.ini.example` already documents.)
3. Assert + verify (idempotent, re-runnable):
   `cd stacks/tautulli/configure && mise exec -- ansible-playbook setup.yml`
   → confirms the API is reachable, Plex is connected **read-only**, history is accumulating;
   fails loudly on a stale token.

### Drills
- **SC-001** now-playing + transcode: play one transcoding + one direct-play stream → both show
  with a correct play-method label.
- **SC-002** read-only: over an observation window, 0 Plex/media writes attributable to Tautulli.
- **SC-003** persistence: note history counts → `DestroyStack`+`DeployStack tautulli` → 0 loss.

## 4. Beszel (US2)

1. `DeployStack beszel` (the **hub only**).
2. **One-time hub admin**: create the superuser at `https://beszel.ragnaforge.xyz` (use
   `BESZEL_ADMIN_*`). Copy the hub's **public key** (Add System dialog shows it) → `.mise.toml`
   `BESZEL_KEY` → `make sync-secrets` (all nodes).
3. `DeployStack beszel-agent-dell`, then `DeployStack beszel-agent-mac` (that node awake). **Both
   are the same generic `stacks/beszel/agent.compose.yaml`** — only the Komodo `server` differs.
4. The hub imports systems from `stacks/beszel/config.yml` (Dell `10.0.0.70:45876`, Mac
   `10.0.0.71:45876`) — no manual "Add System". **Adding a future node** = one `config.yml` line +
   one `beszel-agent-<node>` stack block pointing at the same agent file.
5. **Thresholds**: set disk > 85% (and any CPU/RAM limits) in the hub — **do not** add any
   notification method (no email/webhook/ntfy). Visible indicators only.

### Drills
- **SC-004** one view: both nodes + per-container CPU/RAM, 0 SSH.
- **SC-005** threshold: cross a threshold → visible breach indicator, no push.
- **SC-006** Mac graceful-down: sleep the Mac → node shows down/stale, view intact → wake →
  auto-recovers, 0 re-registration.
- **FR-011** persistence: redeploy the hub → metric history + systems persist.

> **Note:** `ragnaforge-mac` is Apple hardware running **Debian Linux** (not macOS), so its Beszel
> agent is an ordinary Linux agent — identical to the Dell, no VM layer, no macOS caveat. CPU/RAM/
> network + per-container stats are real; **root-disk % and temps** need the host fs/sensors passed
> into the container (host-fs mount + `EXTRA_FILESYSTEMS`, `hwmon`) — add per the pinned Beszel
> version at deploy (same for the Dell agent). Also confirm the listen-port env (`LISTEN` vs `PORT`).

## 5. Front door (US3)

Redeploy `homepage` (already edited): Tautulli + Beszel tiles; the native **Tautulli widget**
shows live streams (key via `HOMEPAGE_VAR_TAUTULLI_KEY`). **SC-008**: both load over valid TLS,
both tiles present, widget live.

## 6. Sign-off (Polish)

- **SC-007** no-push audit: Beszel 0 notification channels, Tautulli 0 notification agents.
- **SC-009** idempotent rebuild: re-run the Tautulli play, re-import Beszel config, redeploy each
  stack → nothing changes.
- **SC-010** footprint: read the tools' own memory from the Beszel per-container view → within
  budget (a few hundred MB).
- Fill the evidence table below, then mark **Phase 6 complete** in `PLAN.md`.

## SC-001…010 evidence table

| SC | What | Result | Date |
|---|---|---|---|
| SC-001 | now-playing + transcode indicator | _pending live run_ | |
| SC-002 | read-only Plex (0 writes) | _pending_ | |
| SC-003 | history survives redeploy | _pending_ | |
| SC-004 | both nodes + per-container, one view | _pending_ | |
| SC-005 | threshold indicator (visible) | _pending_ | |
| SC-006 | Mac down/stale → auto-recover | _pending_ | |
| SC-007 | 0 pushes emitted | _pending_ | |
| SC-008 | TLS + Homepage tiles + widget | _pending_ | |
| SC-009 | idempotent rebuild | _pending_ | |
| SC-010 | observers within footprint budget | _pending_ | |
