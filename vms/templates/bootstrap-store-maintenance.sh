#!/bin/sh
set -eu

phase="${1:-}"
case "$phase" in
  before | after) ;;
  *)
    echo "Usage: bootstrap-store-maintenance.sh before|after" >&2
    exit 2
    ;;
esac

nix_store="${SCRUBS_NIX_STORE:-/run/current-system/sw/bin/nix-store}"
fstrim="${SCRUBS_FSTRIM:-/run/current-system/sw/bin/fstrim}"

echo "Guest disk usage $phase bootstrap store maintenance:"
df -h "$HOME" /nix/store

# Collect only unreachable paths. Never delete profile generations: the
# running system, staged system, and retained rollback generations stay rooted.
# Before apply, recover space from abandoned builds without touching managed
# home state. After reboot, collect inputs no longer held by old processes.
echo "Collecting unreferenced Nix store paths (preserving rollback generations)"
if ! sudo -n "$nix_store" --gc; then
  echo "Bootstrap store maintenance failed; check guest disk usage before retrying." >&2
  exit 1
fi

# Guest free space does not reduce the host's sparse VM allocation until trim.
# Unsupported discard should not turn an otherwise healthy guest into a
# bootstrap failure.
if [ -x "$fstrim" ]; then
  if ! sudo -n "$fstrim" -av; then
    echo "Warning: could not trim the guest; freed blocks may remain allocated on the host." >&2
  fi
fi

echo "Guest disk usage after $phase bootstrap store maintenance:"
df -h "$HOME" /nix/store
