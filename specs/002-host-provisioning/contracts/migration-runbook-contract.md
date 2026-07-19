# Contract: One-Time Migration Runbook

Defines what `docs/runbooks/phase1-migration.md` must contain and guarantee. The
runbook is **documentation, not automation** — it is followed once, by hand, to
move the two current machines onto a fresh OS without losing data.

## Required steps (in order)

| # | Step | Requirement |
|---|---|---|
| 1 | **Preserve** | Snapshot `/srv/nfs` (media + Immich, including an Immich Postgres dump) and export the configs of Vaultwarden, Actual Budget, Home Assistant, and the *arr apps. (FR-001, FR-002) |
| 2 | **Destination** | Preserved artifacts written to storage **independent** of the machine being reinstalled (external drive / workstation), with confirmed capacity for the ~103 GB set. (FR-003) |
| 3 | **Verify** | Integrity-check every artifact and perform **at least one** test restore. (FR-004) |
| 4 | **Gate** | An explicit STOP: do not proceed to any destructive step until verification passes; name what to check. (FR-004, FR-005) |
| 5 | **Reinstall** | Freshly install Debian with SSH enabled — this removes the incumbent k3s. (FR-006) |
| 6 | **Provision** | Run `make provision` against the fresh OS. (FR-007) |
| 7 | **Restore** | Copy the preserved media/photos and app configs back to the Dell; confirm they are readable. (FR-005) |

## Guarantees

- **Verify-before-destroy** ordering: no wipe/reinstall is reachable before
  step 3+4 succeed. (SC-001)
- **Zero data loss**: following the runbook results in 100% of listed data being
  recoverable. (SC-001)
- **k3s only here**: the incumbent cluster's removal is described only in the
  runbook (via reinstall), never in `provision/`. (FR-006, SC-008)
- **One-time**: the runbook is explicitly scoped to the two current machines; the
  reusable path for future/added nodes is `make provision` alone.

## Conformance checks

```sh
# Runbook exists and covers every required step (expect a hit for each keyword):
f=docs/runbooks/phase1-migration.md
for kw in preserve verify restore reinstall "make provision"; do
  grep -qi "$kw" "$f" || echo "runbook missing step: $kw"
done

# The destructive step is gated by verification (manual review):
#   confirm a STOP/verification gate appears BEFORE the reinstall step.
```

Any `missing step` line, or a reinstall step that precedes verification, indicates
non-conformance.
