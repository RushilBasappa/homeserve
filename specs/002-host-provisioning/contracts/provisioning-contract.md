# Contract: Reusable Provisioning

The interface the operator and later phases rely on. A host/repo conforms to the
provisioning contract if and only if all of the following hold.

## Interface (`make` targets)

| Command | Effect |
|---|---|
| `make provision` | Provision **both** nodes to the ready Docker host state. |
| `make provision-dell` | Provision only `ragnaforge-dell` (`--limit dell`). |
| `make provision-mac` | Provision only `ragnaforge-mac` (`--limit mac`). |
| `make check` | Dry run (`ansible-playbook --check`), no changes applied. |

Each target wraps `mise exec -- ansible-playbook -i provision/inventory.yml
provision/playbook.yml [--limit <host>] [--check]`, so secrets come from the
gitignored `.mise.toml`.

## Starting-state precondition

- Target is a **freshly installed Debian 12 host reachable over SSH** with the
  operator's key authorized. Provisioning assumes no prior cluster software and
  performs **no** cleanup of leftovers. (FR-008)

## Definition of "ready Docker host" (postconditions)

After a successful run, on each node:

1. **Docker** — the Docker service is enabled and running; `docker run --rm
   hello-world` succeeds; the admin user is in the `docker` group. (FR-009)
2. **NFS** — Dell exports `/srv/nfs` to `10.0.0.71`; the Mac mounts it (automount)
   and can read **and** write it. (FR-010, SC-005)
3. **Networking** — on the Dell, `sysctl net.ipv4.ip_forward` reads `1` and
   persists across reboot. (FR-011)
4. **SSH baseline** — the admin user exists with the authorized key; `sshd`
   rejects password and root login. (FR-012)
5. **Tailscale** — `tailscale status` shows the node online. (FR-017)

## Invariants

- **Idempotent** — a second consecutive run reports `changed=0`. (FR-013, SC-003)
- **Lean** — provisioning is flat task files, no `roles/` tree. (FR-014)
- **Independent** — one unreachable node does not block provisioning the other.
  (FR-015)
- **No migration logic** — nothing under `provision/` or in the `Makefile`
  performs data preservation, k3s teardown, or OS reinstall. (FR-016, SC-008)
- **Secret-free tree** — no real secret value is tracked; secrets are read from
  `mise`-rendered env only.

## Conformance checks (scriptable)

```sh
# Idempotency: second run makes no changes (inspect the recap: changed=0).
make provision && make provision

# Ready-host checks (run per node, e.g. over SSH):
docker run --rm hello-world                      # Docker works
sysctl -n net.ipv4.ip_forward                    # -> 1 (Dell)
tailscale status                                 # node online
sshd -T | grep -Ei 'passwordauthentication|permitrootlogin'  # both 'no'

# NFS read/write from the Mac:
touch /srv/nfs/.probe && rm /srv/nfs/.probe && echo "NFS rw OK"

# No one-time migration logic leaked into automation (expect NO matches):
grep -rIEi 'k3s|preserve|snapshot|restore|reinstall|teardown' provision/ Makefile \
  && echo "FAIL: migration logic in automation" || echo "OK: automation is migration-free"
```

Any failed check, any `changed>0` on the second run, or any match in the final
grep indicates non-conformance.
