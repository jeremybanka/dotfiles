#!/bin/sh
set -eu

disk="${SCRUBS_INSTALL_DISK:-/dev/vda}"
root_mount=/mnt
seed_mount=/mnt/host-scrubs-seed

if [ ! -d "$seed_mount" ]; then
  echo "Seed mount not found at $seed_mount" >&2
  exit 1
fi

echo "Partitioning $disk"
parted --script "$disk" -- \
  mklabel gpt \
  mkpart ESP fat32 1MiB 512MiB \
  set 1 esp on \
  mkpart primary ext4 512MiB 100%

udevadm settle

mkfs.fat -F 32 -n ESP "${disk}1"
mkfs.ext4 -F -L nixos "${disk}2"

mount /dev/disk/by-label/nixos "$root_mount"
mkdir -p "$root_mount/boot"
mount /dev/disk/by-label/ESP "$root_mount/boot"

nixos-generate-config --root "$root_mount"

cp "$seed_mount/base.nix" "$root_mount/etc/nixos/scrubs-seed-base.nix"

cat > "$root_mount/etc/nixos/configuration.nix" <<'EOF'
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./scrubs-seed-base.nix
  ];
}
EOF

nixos-install --no-root-passwd

echo
echo "Seed image installed."
echo "Power the guest off, then run:"
echo "  just export-seed-image scrubs-seed /absolute/path/to/nixos-base-aarch64.qcow2"
