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
# The provision targets depend on `deps`, so a fresh control node is
# self-sufficient — no undocumented `ansible-galaxy` step (SC-009, FR-007).

ANSIBLE_PLAYBOOK := mise exec -- ansible-playbook -i provision/inventory.yml provision/playbook.yml

.PHONY: deps provision provision-dell provision-mac check

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
