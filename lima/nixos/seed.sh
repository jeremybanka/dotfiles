#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
scrubs_dir="$repo_root/lima/nixos"
seed_dir="$scrubs_dir/seed"
instance_name="${1:-scrubs-seed}"
template_file="$scrubs_dir/seed.local.yaml"
seed_iso="${SCRUBS_SEED_ISO:-}"

if [ -f "$scrubs_dir/settings.env" ]; then
  # shellcheck disable=SC1090
  . "$scrubs_dir/settings.env"
fi

seed_iso="${SCRUBS_SEED_ISO:-$seed_iso}"

if [ -z "$seed_iso" ]; then
  echo "Set SCRUBS_SEED_ISO in the environment or lima/nixos/settings.env." >&2
  exit 1
fi

if printf '%s' "$seed_iso" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://'; then
  iso_location="$seed_iso"
else
  iso_location=$(cd "$(dirname "$seed_iso")" && pwd)/$(basename "$seed_iso")
fi

escaped_iso_location=$(printf '%s\n' "$iso_location" | sed 's/[&|]/\\&/g')
escaped_seed_dir=$(printf '%s\n' "$seed_dir" | sed 's/[&|]/\\&/g')

sed \
  -e "s|REPLACE_WITH_SEED_ISO|$escaped_iso_location|g" \
  -e "s|REPLACE_WITH_SEED_DIR|$escaped_seed_dir|g" \
  "$scrubs_dir/seed.yaml" > "$template_file"

echo "Starting installer instance $instance_name"
limactl start --name="$instance_name" --video "$template_file"

echo
echo "Inside the installer console, run:"
echo "  sudo -i"
echo "  /mnt/host-scrubs-seed/install.sh"
echo
echo "When installation completes, shut the guest down from inside NixOS."
echo "Then export the reusable base image with:"
echo "  ./lima/nixos/export-seed-image.sh $instance_name /absolute/path/to/nixos-base-aarch64.qcow2"
