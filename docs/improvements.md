# Improvements & Open Ideas

A running backlog of things worth improving — captured so they aren't lost, not
committed work. Each entry states the **context**, the **problem**, the **options**
(with trade-offs), a **recommendation**, and **open questions**. Pick them up in
the phase where they fit.

Status legend: 💡 idea · 🔬 needs a spike · 📌 decided, not yet built · ✅ done.

---

## 1. 💡 Auto-deploy on push to `main`

**Context.** Today the deploy flow is deliberate and two-step (push → Sync →
Deploy), by design (FR-007). Changing a stack means: `git push`, then a manual
`RunSync`, then a manual `DeployStack`. See the deploy model in
[`runbooks/phase2-komodo.md`](./runbooks/phase2-komodo.md).

**Goal.** A push to `main` should be able to deploy the affected stack(s)
automatically — at least for chosen stacks — without a human running two commands.

**The blocker today.** Komodo Core is **LAN/Tailscale-only** (FR-009). A normal
git webhook is a request *from GitHub's servers*, which cannot reach a private
Core. So the built-in webhook can't fire until Core is publicly reachable.

**Options.**

- **A. Komodo per-stack / per-sync git webhook** (the native mechanism, task
  T020). A push hits a Komodo webhook endpoint; the stack (or a ResourceSync with
  `deploy = true`) reconciles and deploys. Signed with `KOMODO_WEBHOOK_SECRET`.
  - Needs: Core reachable from GitHub → **Phase 3** (Traefik + TLS + a public
    hostname). Ideally expose *only* the `/listener/...` webhook route publicly,
    not the whole UI/API.
  - Pro: zero extra infra once Core is exposed; Komodo-native; opt-in per stack.
  - Con: pulls a piece of Core onto the public internet; must be locked down
    (secret + path scoping + maybe Cloudflare in front).

- **B. GitHub Actions → Komodo API over Tailscale** *(keeps Core private)*. A
  workflow on push to `main` calls Core's API (`RunSync` then `DeployStack`) using
  a Komodo API key stored as a GitHub secret. The runner reaches the LAN-only Core
  by joining the tailnet — either a **self-hosted runner on a node**, or the
  [`tailscale/github-action`](https://github.com/tailscale/github-action) on a
  hosted runner.
  - Pro: Core stays fully private (no public exposure); CI can gate on tests, lint
    the TOML, or deploy only changed stacks; full control over *what* deploys.
  - Con: needs a runner with tailnet access; an API key lives in GitHub secrets.

- **C. Poll-and-reconcile on the Dell.** A `systemd` timer / cron on the Dell runs
  `RunSync` (optionally with deploy) every N minutes.
  - Pro: dead simple, no inbound, no exposure.
  - Con: not truly "on push" (polling lag); a blanket auto-deploy erodes the
    deliberate gate unless scoped to specific stacks.

**Recommendation.** 📌 Prefer **B** (Actions + Tailscale + API) if we want
auto-deploy *before* Phase 3 or want to keep Core off the public internet
long-term; otherwise adopt **A** once Phase 3 exposes Core. Either way, keep it
**opt-in per stack** and **never auto-deploy stateful stacks** without a manual
gate — the deliberate-deploy guarantee (FR-007) exists on purpose. A good default:
auto-deploy only stateless/low-risk stacks; leave databases and anything on the
Dell manual.

**Open questions.**
- Do we want CI to run checks (TOML validity, secret-free grep) *before* it
  triggers a deploy? (Leans toward option B.)
- Per-stack allowlist for auto-deploy, or a tag (e.g. `auto-deploy`) honored by
  the workflow?

---

## 2. 💡 Better secret distribution to the nodes (no manual `.mise.toml` copy)

**Context.** Real secrets live in the gitignored `.mise.toml`. During Phase 2
bring-up we **manually copied** that file from the workstation onto each node
(`ssh <node> 'cat > ~/homeserve/.mise.toml'`), because compose runs *on the node*
and resolves `${VAR}` from the environment there. See the as-built note in
[`runbooks/phase2-komodo.md`](./runbooks/phase2-komodo.md#as-built-notes--first-live-bring-up-2026-07-19).

**Problem.** Manual copy is awkward and drift-prone: rotate a secret and you must
re-copy to every node; add a node and you must remember to seed it; the secret
sits as plaintext on each node. It doesn't scale past a couple of hosts.

**The constraint.** *Some* mechanism must place each secret where it's resolved.
For the current `${VAR}`-in-compose path, that's the Periphery process env on each
node. The question is how to distribute *without* hand-copying.

**Options.**

- **A. Move stack secrets into Komodo secret Variables (`[[VAR]]`).** Store each
  secret once in Core's DB (marked secret → redacted in API/logs/TOML export),
  reference `[[VAR]]` in compose instead of `${VAR}`. Core injects it at deploy
  time, so **nodes need no stack-secret file at all**. This is the R4 fallback we
  already documented.
  - Pro: single source of truth (Core, on the Dell); **eliminates the per-node
    copy entirely** for stack secrets; git stays secret-free; add-a-node needs no
    secret seeding.
  - Con: secrets now live in Core's Mongo rather than a mise file — a deliberate
    shift in the model (still satisfies "secret-free git", but management moves to
    Core's UI/API). Core's *own* bootstrap secrets (DB password, JWT, passkey)
    still need to reach the Dell at bring-up — but that's **one** node, not every
    node. `KOMODO_PASSKEY` still has to match on each Periphery node.

- **B. SOPS + age, native to `mise`.** Commit an **encrypted** secrets file to git;
  each node holds an `age` key and decrypts on use. `mise` has first-class
  sops/age support. Distribution becomes `git pull` (the encrypted blob travels in
  the repo) + a one-time per-node decryption key.
  - Pro: git-native and versioned (encrypted), no plaintext copying, rotation is a
    commit; only the age key is distributed once per node.
  - Con: key management (each node needs its age key seeded once — but that's a
    single small secret, and can be done at provision time).

- **C. Ansible-templated `.mise.toml`.** Extend the Phase-1 Ansible to render
  `.mise.toml` onto each node from a single source (a vault, or SOPS), as one
  idempotent `make secrets` / playbook run.
  - Pro: reuses existing tooling; one command; repeatable; fits "add a node = run
    the playbook."
  - Con: secrets still land as plaintext on nodes (same as today), just automated
    and repeatable instead of manual.

- **D. A dedicated secrets manager** (Infisical / Doppler / Vault / Bitwarden
  Secrets Manager) that nodes or Komodo fetch from at deploy.
  - Pro: proper rotation, audit, dynamic secrets.
  - Con: another service to run and depend on — heavier than this fleet warrants
    right now.

**Recommendation.** 📌 A two-layer approach:
1. **Stack secrets → Komodo secret Variables (`[[VAR]]`, option A).** This removes
   the per-node copy problem for everything a *stack* consumes, using Komodo's
   native mechanism. Biggest win for the least new infra.
2. **The few genuine per-node/bootstrap secrets** (`KOMODO_PASSKEY`, and Core's
   own secrets on the Dell) → distribute via **SOPS+age in `mise`** (option B) or
   **Ansible templating** (option C), so seeding a node is `git pull` + one key, or
   one `make` target — never a manual `scp`.

This keeps git secret-free, makes "add a node" a repeatable step, and reserves a
full secrets manager (D) for if/when the fleet grows enough to need audit and
rotation.

**Open questions.**
- Are we comfortable moving stack secrets from the mise file into Core's DB?
  (Changes the FR-006 mechanism from "mise-rendered env" to "Komodo Variable" —
  both keep git clean; worth an explicit decision.)
- SOPS+age vs Ansible-templating for the bootstrap secrets — which fits the
  provisioning flow better? (Likely a small Phase-1 spike.)
- Where does the age key / vault credential itself come from on a fresh node
  (the "secret-zero" problem)?

---

_Add new ideas below as they come up._
