# Makefile — the one memorable entry point for host provisioning.
#
# Every target wraps `mise exec -- ansible-playbook` so secrets (the Tailscale
# auth key) are rendered from the gitignored `.mise.toml` into the environment
# and never touch a tracked file or the shell history (research.md R8, R11).
#
#   make deps             install the Ansible collections the playbook needs
#   make provision        provision BOTH nodes to the ready Docker host state
#   make provision-dell   provision only ragnaforge-dell  (--limit dell)
#   make provision-mac    provision only ragnaforge-mac   (--limit mac)
#   make check            dry run (--check), applies no changes
#
# Phase 2 — Komodo control-plane bootstrap (research R3). Run ON the node itself:
#   make komodo-core        bring up Komodo Core + MongoDB   (Dell only)
#   make komodo-periphery   bring up the Periphery agent     (each node)
#
# Secrets — run from the workstation (control node):
#   make sync-secrets       push the repo .mise.toml to every node, in sync
#
# Phase 3 — Edge, DNS & TLS (research R7, R10):
#   make edge-network       create the shared external `traefik` network (Dell)
#   make preflight          GO/NO-GO for the public VPN endpoint (run first)
#
# The provision targets depend on `deps`, so a fresh control node is
# self-sufficient — no undocumented `ansible-galaxy` step (SC-009, FR-007).

ANSIBLE_PLAYBOOK := mise exec -- ansible-playbook -i provision/inventory.yml provision/playbook.yml

# Both bootstrap targets wrap `mise exec -- docker compose`, so Core's secrets
# (DB password, JWT/webhook secrets, passkey) are rendered from the gitignored
# `.mise.toml` into the environment and never touch a tracked file (research R7).
KOMODO_CORE_COMPOSE      := mise exec -- docker compose -f komodo/bootstrap/core.compose.yaml
KOMODO_PERIPHERY_COMPOSE := mise exec -- docker compose -f komodo/bootstrap/periphery.compose.yaml

.PHONY: deps provision provision-dell provision-mac check komodo-core komodo-periphery sync-secrets edge-network preflight

deps:
	mise exec -- ansible-galaxy collection install -r provision/requirements.yml

provision: deps
	$(ANSIBLE_PLAYBOOK)

provision-dell: deps
	$(ANSIBLE_PLAYBOOK) --limit dell

provision-mac: deps
	$(ANSIBLE_PLAYBOOK) --limit mac

check: deps
	$(ANSIBLE_PLAYBOOK) --check

# --- Phase 2: Komodo control plane (run on the target node) ---

# Dell only. Requires komodo/bootstrap/core.env (cp from core.env.example first).
komodo-core:
	$(KOMODO_CORE_COMPOSE) up -d

# Each node (Dell + Mac).
komodo-periphery:
	$(KOMODO_PERIPHERY_COMPOSE) up -d

# Push the repo's .mise.toml to every node so secrets stay in sync with the
# source. Idempotent — only changed nodes are touched, and Periphery is refreshed
# there so new ${VAR} values take effect. Run after editing .mise.toml.
sync-secrets:
	mise exec -- ansible-playbook -i provision/inventory.yml provision/sync-secrets.yml

# --- Phase 3: Edge, DNS & TLS ---

# Create the shared external Docker network Traefik and every HTTP app join.
# Run ON the Dell. Idempotent — a no-op if the network already exists (research R10).
edge-network:
	docker network inspect traefik >/dev/null 2>&1 || docker network create traefik

# The checks-first GO/NO-GO gate for the public VPN endpoint (US7, research R7).
# Run from the workstation BEFORE building the VPN slice. Pass an external UDP
# probe result to complete check 2, e.g.:
#   EXTERNAL_UDP_51820=open make preflight
preflight:
	./scripts/preflight-public-endpoint.sh
