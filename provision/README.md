# `provision/` — Host provisioning (Ansible)

Lean **Ansible** that turns a freshly installed Debian laptop into a ready Docker
host. This is deliberately small — a handful of task files, **not** a sprawling
role tree.

Run it from the repo root via the `Makefile`:

```sh
make deps             # install the Ansible collections (ansible.posix)
make provision        # both nodes → ready Docker host state
make provision-dell   # just ragnaforge-dell   (--limit dell)
make provision-mac    # just ragnaforge-mac    (--limit mac)
make check            # dry run (--check), applies no changes
```

The `provision*` targets run `make deps` first, and each wraps
`mise exec -- ansible-playbook …` so the only secret (`TAILSCALE_AUTHKEY`) is
rendered from the gitignored `.mise.toml` — never a tracked file.

## Scope

What provisioning is responsible for (Phase 1):

- Install **Docker Engine** (official apt repo) and enable the service.
- **NFS**: the Dell exports `/srv/nfs`; the Mac mounts it via systemd automount
  (so a down server never wedges the Mac's boot).
- Kernel `sysctl` — `net.ipv4.ip_forward=1` on the Dell (future VPN subnet router).
- A consistent **admin user + hardened SSH baseline** (key-only) on both nodes.
- Install and **enroll Tailscale** idempotently (only runs `tailscale up` when the
  node isn't already connected).

Everything above the OS — the apps themselves — is Docker Compose managed by
Komodo, **not** Ansible. Provisioning stops at "a clean Docker host."

Provisioning assumes a **freshly installed Debian + SSH** starting state and
contains **zero** one-time migration steps — those one-time, irreversible steps
for the two current machines live only in the runbook:
[`docs/runbooks/phase1-migration.md`](../docs/runbooks/phase1-migration.md).

## Layout

```text
provision/
├── inventory.yml        # ragnaforge-dell (10.0.0.70), ragnaforge-mac (10.0.0.71)
├── playbook.yml         # includes the task files per host role
├── requirements.yml     # Ansible collections (ansible.posix)
├── group_vars/
│   └── all.yml          # non-secret vars: admin user, SSH public key, NFS paths
└── tasks/
    ├── docker.yml       # Docker Engine via official apt repo
    ├── ssh-baseline.yml # admin user + authorized key + sshd hardening
    ├── tailscale.yml    # install + idempotent enroll via TAILSCALE_AUTHKEY
    ├── sysctl.yml       # ip_forward drop-in (Dell)
    ├── nfs-server.yml   # Dell: nfs-kernel-server + export /srv/nfs
    └── nfs-client.yml   # Mac: nfs-common + systemd-automount mount
```

Host roles are driven by inventory groups: `docker_hosts` (both) get Docker +
SSH + Tailscale; `dell` also gets sysctl + the NFS server; `mac` gets the NFS
client.

## Verifying

See [`../specs/002-host-provisioning/quickstart.md`](../specs/002-host-provisioning/quickstart.md)
and the contracts under `specs/002-host-provisioning/contracts/` for the
conformance checks — idempotency (`make provision` twice → `changed=0`), a test
container, NFS read/write, `ip_forward`, `sshd` hardening, and Tailscale
reachability.
