#!/usr/bin/env bash
#
# cleanup-all.sh — run the one-time node teardown on BOTH Ragnaforge nodes.
#
# Run this from your control machine (the Mac). For each node it copies
# cleanup-node.sh over and runs it with sudo over an interactive SSH session, so
# sudo can prompt for your password on the tty (you'll enter it once per node).
#
# Dry-run by default — it previews on each node until you pass --yes.
#
#   bash scripts/cleanup-all.sh          # preview both nodes (no changes)
#   bash scripts/cleanup-all.sh --yes    # actually wipe both nodes
#
# Uses your ~/.ssh/config aliases (ragnaforge-dell / ragnaforge-mac).

set -uo pipefail

HOSTS=(ragnaforge-dell ragnaforge-mac)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE_SCRIPT="$SCRIPT_DIR/cleanup-node.sh"

FLAGS=""
for a in "$@"; do
  case "$a" in
    --yes|-y)  FLAGS="--yes" ;;
    --dry-run) FLAGS="" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

[ -f "$NODE_SCRIPT" ] || { echo "missing $NODE_SCRIPT" >&2; exit 1; }

echo "Target nodes: ${HOSTS[*]}"
echo "Mode: $([ -n "$FLAGS" ] && echo 'LIVE (--yes) — this deletes data' || echo 'dry-run (preview only)')"

for host in "${HOSTS[@]}"; do
  printf '\n======================================================\n'
  printf '  %s\n' "$host"
  printf '======================================================\n'
  if ! scp -q "$NODE_SCRIPT" "$host:/tmp/cleanup-node.sh"; then
    echo "!! could not copy the script to $host — skipping (is it reachable?)" >&2
    continue
  fi
  # -t allocates a tty so sudo can prompt for the password on this node.
  ssh -t "$host" "sudo bash /tmp/cleanup-node.sh ${FLAGS}; rm -f /tmp/cleanup-node.sh" \
    || echo "!! cleanup on $host exited non-zero (see output above)" >&2
done

printf '\nDone. '
[ -n "$FLAGS" ] && echo "Both nodes wiped (SSH preserved). Next: make provision" \
                || echo "That was a preview. Re-run with --yes to apply."
