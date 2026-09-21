#!/bin/sh
# Run as root in a disposable guest, immediately before shutdown and export.
# Keep the installed system; erase all user data and per-machine identity.
set -eu
export PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin
test "$(id -u)" = 0
test -d /nix/store
cd /

# NixOS keeps cloud-init in its service closure rather than the global PATH.
cloud_init=$(command -v cloud-init || true)
if [ -z "$cloud_init" ]; then
  cloud_init=$(sed -n 's|^ExecStart=\([^ ]*/bin/cloud-init\) .*|\1|p' /etc/systemd/system/cloud-init-local.service)
fi
test -n "$cloud_init"
test -x "$cloud_init"

# Prevent services from restoring their persisted identity during shutdown.
for unit in tailscaled-autoconnect.service tailscaled.service systemd-random-seed.service; do
  if [ "$(systemctl show --property=LoadState --value "$unit")" != not-found ]; then
    systemctl stop "$unit"
  fi
done

for guest_home in /root /home/*; do
  [ -d "$guest_home" ] || continue
  # Do not follow home symlinks or traverse nested mounts into another volume.
  test ! -L "$guest_home"
  find "$guest_home" -xdev -mindepth 1 -delete
done
rm -rf /var/lib/tailscale /var/lib/private/tailscale /run/scrubs-clean-auth
rm -f /etc/ssh/ssh_host_* /var/lib/systemd/random-seed
rm -f /var/lib/systemd/credential.secret /boot/loader/random-seed
rm -f /var/lib/dbus/machine-id
rm -f /etc/machine-id
: > /etc/machine-id
rm -rf /var/lib/scrubs

# Also remove old cloud-init payloads, logs and scripts, which can contain
# instance-specific authorized keys and bootstrap data.
"$cloud_init" clean --logs --seed
rm -rf /var/lib/cloud
rm -rf /tmp/mise-cache
find /tmp /var/tmp -xdev -mindepth 1 -delete

nix-collect-garbage -d
# Nix recreates this default profile symlink while collecting as root.
if [ -L /root/.nix-profile ]; then
  rm /root/.nix-profile
fi
fstrim -av
sync

test ! -s /etc/machine-id
test ! -e /var/lib/dbus/machine-id
test ! -e /var/lib/tailscale
test ! -e /var/lib/private/tailscale
test ! -e /var/lib/systemd/random-seed
test ! -e /var/lib/systemd/credential.secret
test ! -e /boot/loader/random-seed
test ! -e /var/lib/cloud
for key in /etc/ssh/ssh_host_*; do
  test ! -e "$key"
done
for guest_home in /root /home/*; do
  [ -d "$guest_home" ] || continue
  remaining=$(find "$guest_home" -mindepth 1 -print -quit)
  if [ -n "$remaining" ]; then
    echo "Guest data remains after cleanup: $remaining" >&2
    exit 1
  fi
done
echo 'Base-image cleanup verified.'
