# `provision/` — Host provisioning (Ansible)

Lean **Ansible** that turns a fresh Debian laptop into a ready Docker host. This
is deliberately small — a handful of tasks, **not** a sprawling role tree.

## Scope

What provisioning is responsible for (Phase 1):

- Install **Docker Engine**.
- Install **NFS** packages and set up mounts (`/srv/nfs` on the Dell, mounted on
  the Mac).
- Kernel `sysctl` (IP forwarding, for the VPN subnet router).
- Baseline user / SSH configuration.
- Verify **Tailscale** is present on both nodes.

Everything above the OS — the apps themselves — is Docker Compose managed by
Komodo, **not** Ansible. Provisioning stops at "a clean Docker host."

## Layout (added in Phase 1)

Expected to grow into a minimal inventory + playbook, e.g.:

```text
provision/
├── inventory.yml     # ragnaforge-dell, ragnaforge-mac
├── playbook.yml      # docker, nfs, sysctl, ssh baseline
└── ...
```

Currently empty — populated in **Phase 1 (Migration & host provisioning)**.
Deliverable there: `make provision` → two Docker hosts.
