#!/usr/bin/env bash
#
# cleanup-node.sh — ONE-TIME, DESTRUCTIVE teardown of a Ragnaforge node.
#
# Brings a live k3s box back to a clean slate so `make provision` can run against
# it. It removes k3s, Docker, all container/app data, the /srv/nfs data set, and
# package caches/logs. It deliberately does NOT touch:
#   - the OS, kernel, bootloader, or network config
#   - the openssh server, /etc/ssh (host keys + config), or any ~/.ssh
#     (authorized_keys) — so you can always SSH back in.
#
# This is the in-place equivalent of the runbook's "reinstall the OS" step. It is
# NOT part of the reusable provisioning (that must stay migration-free, SC-008),
# which is why it lives in scripts/, not provision/.
#
# SAFETY: dry-run by default. It only PRINTS what it would do until you pass
# --yes. Run it as root (via sudo).
#
#   sudo bash cleanup-node.sh            # preview (dry-run)
#   sudo bash cleanup-node.sh --yes      # actually do it
#
# Extend DATA_PATHS below if you keep app data outside /srv/nfs.

set -uo pipefail

# --- Paths whose CONTENTS get wiped (the dirs themselves are kept) -------------
DATA_PATHS=(
  /srv/nfs          # the ~103 GB media/config namespace
)

# --- Arg parsing ---------------------------------------------------------------
DRY_RUN=1
for a in "$@"; do
  case "$a" in
    --yes|-y)   DRY_RUN=0 ;;
    --dry-run)  DRY_RUN=1 ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "This must run as root. Re-run with: sudo bash $0 $*" >&2
  exit 1
fi

# --- Helpers -------------------------------------------------------------------
c_head=$'\033[1;34m'; c_warn=$'\033[1;33m'; c_ok=$'\033[1;32m'; c_off=$'\033[0m'
log()  { printf '\n%s==>%s %s\n' "$c_head" "$c_off" "$*"; }
note() { printf '    %s\n' "$*"; }

# run "<shell command>" — echoes it; executes only when not in dry-run, and never
# aborts the script on a single failure (cleanup is best-effort).
run() {
  local cmd="$*"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] %s\n' "$cmd"
  else
    printf '  + %s\n' "$cmd"
    eval "$cmd" || printf '    %s(ignored failure)%s\n' "$c_warn" "$c_off"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# --- Banner --------------------------------------------------------------------
log "Ragnaforge node cleanup on $(hostname) — $([ "$DRY_RUN" -eq 1 ] && echo 'DRY RUN (nothing will change)' || echo 'LIVE — THIS DELETES DATA')"
note "Disk usage BEFORE:"; df -h / /srv 2>/dev/null | sed 's/^/      /'

if [ "$DRY_RUN" -eq 0 ]; then
  printf '\n%sThis will PERMANENTLY delete k3s, Docker, and all data on %s.%s\n' "$c_warn" "$(hostname)" "$c_off"
  printf 'Type EXACTLY "wipe %s" to proceed: ' "$(hostname)"
  read -r confirm < /dev/tty || true
  if [ "$confirm" != "wipe $(hostname)" ]; then
    echo "Confirmation did not match — aborting, nothing changed."; exit 1
  fi
fi

# --- 1. Remove k3s (official uninstallers handle containerd/CNI/mounts/units) ---
log "Removing k3s"
if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
  run "/usr/local/bin/k3s-uninstall.sh"
elif [ -x /usr/local/bin/k3s-agent-uninstall.sh ]; then
  run "/usr/local/bin/k3s-agent-uninstall.sh"
else
  note "no k3s uninstaller found — clearing leftover state directly"
fi
# Belt-and-suspenders: remove any residual k3s/kube state and interfaces.
run "systemctl disable --now k3s k3s-agent 2>/dev/null"
run "rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet /var/lib/cni /run/k3s /run/flannel /var/lib/rook"
for iface in cni0 flannel.1 kube-ipvs0; do
  run "ip link delete $iface 2>/dev/null"
done

# --- 2. Remove Docker + all its data -------------------------------------------
log "Removing Docker and container data"
if have docker; then
  run "docker system prune -af --volumes 2>/dev/null"
  run "systemctl disable --now docker docker.socket containerd 2>/dev/null"
fi
if have apt-get; then
  run "DEBIAN_FRONTEND=noninteractive apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker.io containerd 2>/dev/null"
fi
run "rm -rf /var/lib/docker /var/lib/containerd /etc/docker /var/run/docker.sock"
run "ip link delete docker0 2>/dev/null"

# --- 3. Wipe the data set (contents only; keep the directories) ----------------
log "Wiping data directories"
for p in "${DATA_PATHS[@]}"; do
  if [ -d "$p" ]; then
    note "emptying $p"
    run "find $p -mindepth 1 -delete 2>/dev/null"
  else
    note "$p does not exist — skipping"
  fi
done
# Stale NFS export config from any prior provisioning (safe if absent).
run "rm -f /etc/exports.d/ragnaforge.exports 2>/dev/null"

# --- 4. Clear caches and logs --------------------------------------------------
log "Clearing caches and logs"
if have apt-get; then
  run "apt-get clean"
  run "rm -rf /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb"
fi
if have journalctl; then
  run "journalctl --rotate 2>/dev/null"
  run "journalctl --vacuum-time=1s 2>/dev/null"
fi
run "rm -rf /tmp/* /var/tmp/* 2>/dev/null"
run "rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*.old 2>/dev/null"
run "sync"
[ -w /proc/sys/vm/drop_caches ] && run "sh -c 'echo 3 > /proc/sys/vm/drop_caches'"

# --- 5. Re-assert SSH access (must survive the wipe) ---------------------------
log "Verifying SSH access is intact"
if have systemctl; then
  run "systemctl enable --now ssh 2>/dev/null"
fi
note "openssh-server present: $(dpkg -l openssh-server 2>/dev/null | grep -q '^ii' && echo yes || echo 'UNKNOWN — do not reboot until confirmed')"
note "/etc/ssh host keys: $(ls /etc/ssh/ssh_host_*_key 2>/dev/null | wc -l | tr -d ' ') present (untouched)"
for h in /home/*/.ssh/authorized_keys /root/.ssh/authorized_keys; do
  [ -f "$h" ] && note "authorized_keys kept: $h"
done

# --- Done ----------------------------------------------------------------------
log "Cleanup complete on $(hostname)"
note "Disk usage AFTER:"; df -h / /srv 2>/dev/null | sed 's/^/      /'
if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n%sThat was a DRY RUN — nothing changed. Re-run with --yes to apply.%s\n' "$c_ok" "$c_off"
else
  printf '\n%sNode wiped. SSH preserved. Ready for: make provision%s\n' "$c_ok" "$c_off"
  note "A reboot is recommended to clear any lingering k3s/docker network state."
fi
