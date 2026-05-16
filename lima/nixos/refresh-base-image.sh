#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
scrubs_dir="$repo_root/lima/nixos"
source_image="${1:-}"
output_path="${2:-}"
instance_name="${3:-scrubs-refresh}"
vm_type="${SCRUBS_REFRESH_VM_TYPE:-${SCRUBS_VM_TYPE:-vz}}"
guest_arch="${SCRUBS_REFRESH_ARCH:-${SCRUBS_ARCH:-aarch64}}"
delete_instance="${SCRUBS_REFRESH_DELETE_INSTANCE:-true}"

usage() {
  echo "Usage: $0 /absolute/path/to/current-base.qcow2 /absolute/path/to/refreshed-base.qcow2 [instance-name]" >&2
  exit 1
}

if [ -z "$source_image" ] || [ -z "$output_path" ]; then
  usage
fi

source_image=$(cd "$(dirname "$source_image")" && pwd)/$(basename "$source_image")

if [ ! -f "$source_image" ]; then
  echo "Base image not found: $source_image" >&2
  exit 1
fi

output_dir=$(cd "$(dirname "$output_path")" && pwd)
output_path="$output_dir/$(basename "$output_path")"

if [ "$source_image" = "$output_path" ]; then
  echo "Refusing to overwrite the source image in place." >&2
  echo "Write to a new path, then replace the old image after you validate it." >&2
  exit 1
fi

echo "Refreshing base image from $source_image"
echo "Using Lima instance $instance_name with vmType=$vm_type arch=$guest_arch"

SCRUBS_BASE_IMAGE="$source_image" \
SCRUBS_VM_TYPE="$vm_type" \
SCRUBS_ARCH="$guest_arch" \
"$scrubs_dir/bootstrap.sh" "$instance_name"

"$scrubs_dir/export-seed-image.sh" "$instance_name" "$output_path"

if [ "$delete_instance" = "true" ]; then
  echo "Deleting temporary Lima instance $instance_name"
  limactl delete "$instance_name" >/dev/null 2>&1 || true
fi

echo "Refreshed base image written to $output_path"
