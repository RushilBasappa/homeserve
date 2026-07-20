# Quickstart / Validation: Storage

Behavioral proof that the shared namespace works. Run after
`provision/playbook.yml` applies `storage-layout.yml`. Paste results into
`docs/runbooks/phase4-storage.md`. Each check maps to a success criterion.

**Prereqs**: Phases 1–3 applied; Dell (10.0.0.70) and Mac (10.0.0.71) up and on the
LAN; `ssh ragnaforge-dell` and `ssh ragnaforge-mac` work.

---

## Check 1 — The standard tree exists with correct ownership (SC-003, FR-003/FR-004)

On the Dell:

```bash
ssh ragnaforge-dell 'ls -la /srv/nfs /srv/nfs/media /srv/nfs/downloads &&
  stat -c "%n %U:%G %a" /srv/nfs/media/movies /srv/nfs/media/tv \
    /srv/nfs/downloads/complete /srv/nfs/downloads/incomplete /srv/nfs/photos'
```

**Expected**: all five leaf paths listed, each `rushil:rushil 2775`.

---

## Check 2 — Cross-node consistency: write on Dell, read on Mac (SC-001, FR-001)

```bash
ssh ragnaforge-dell 'echo "hello-from-dell" > /srv/nfs/downloads/incomplete/_p4test'
ssh ragnaforge-mac  'cat /srv/nfs/downloads/incomplete/_p4test'          # → hello-from-dell
ssh ragnaforge-mac  'echo "edited-on-mac" >> /srv/nfs/downloads/incomplete/_p4test'
ssh ragnaforge-dell 'cat /srv/nfs/downloads/incomplete/_p4test'          # → both lines
ssh ragnaforge-dell 'rm /srv/nfs/downloads/incomplete/_p4test'
```

**Expected**: the Mac reads the Dell's file with identical contents; the Mac's append
is visible back on the Dell within seconds — one consistent namespace, no manual
mount step on the Mac.

---

## Check 3 — On-demand automount, no manual mount (SC-001, FR-002)

```bash
ssh ragnaforge-mac 'systemctl status srv-nfs.automount --no-pager | head -3'
ssh ragnaforge-mac 'ls /srv/nfs/media >/dev/null && echo "access OK (mount activated on demand)"'
ssh ragnaforge-mac 'findmnt /srv/nfs'                                     # shows the nfs mount now active
```

**Expected**: the automount unit is active (loaded/waiting or running); first access
succeeds and triggers the real mount; `findmnt` confirms an `nfs` mount from
`10.0.0.70:/srv/nfs`.

---

## Check 4 — Server-down Mac boot does not wedge (SC-002, FR-002, edge case)

> Disruptive-ish; do when convenient. Simulates the "server absent at boot" case.

```bash
# On the Dell, briefly stop the export:
ssh ragnaforge-dell 'sudo systemctl stop nfs-server'
# Reboot the Mac (or at minimum: restart the automount) and confirm it comes up:
ssh ragnaforge-mac 'sudo systemctl restart srv-nfs.automount && echo "automount restarted, boot-equivalent OK"'
# Restore the server, then confirm access recovers on next touch:
ssh ragnaforge-dell 'sudo systemctl start nfs-server'
ssh ragnaforge-mac  'ls /srv/nfs/media && echo "recovered on access"'
```

**Expected**: the Mac boots / the automount comes up **without hanging** while the
server is down; once the server is back, first access to `/srv/nfs` succeeds — no
reboot loop, no manual mount.

---

## Check 5 — No stateful data on the Mac (SC-005, FR-007)

```bash
ssh ragnaforge-mac 'docker volume ls && echo "---" && docker ps --format "{{.Names}}: {{.Mounts}}"'
```

**Expected**: no Docker named volume or bind mount on the Mac holds a database or app
config (Phases 1–3 kept all state on the Dell). Record the result; justify any
exception in the runbook.

---

## Check 6 — Growth-path runbook resolves (SC-004, FR-006)

- Open `docs/CONVENTIONS.md`, find the "documented in Phase 4" mergerfs reference,
  and confirm it links/points to `docs/runbooks/phase4-storage.md`.
- Confirm that runbook's growth section states the export path (`/srv/nfs`) — and
  therefore every app mount — is **unchanged** when a USB disk is pooled in via
  mergerfs.

**Expected**: one hop from the reference to the runbook; the invariant is stated.

---

## Done when

All six checks pass and their outputs are recorded in
`docs/runbooks/phase4-storage.md`. At that point the shared namespace is real,
proven, and documented — Phase 5 and Phase 6 can mount `contracts/media-layout.md`
paths with confidence.
