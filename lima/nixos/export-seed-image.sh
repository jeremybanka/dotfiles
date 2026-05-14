#!/bin/sh
set -eu

instance_name="${1:-scrubs-seed}"
output_path="${2:-}"

if [ -z "$output_path" ]; then
  echo "Usage: $0 INSTANCE /absolute/path/to/nixos-base-aarch64.qcow2" >&2
  exit 1
fi

instance_dir="$HOME/.lima/$instance_name"
disk_path="$instance_dir/disk"

if [ ! -f "$disk_path" ]; then
  echo "Instance disk not found: $disk_path" >&2
  exit 1
fi

output_dir=$(cd "$(dirname "$output_path")" && pwd)
output_file="$output_dir/$(basename "$output_path")"

echo "Stopping Lima instance $instance_name if it is still running"
limactl stop "$instance_name" >/dev/null 2>&1 || true

echo "Exporting base image to $output_file"
qemu-img convert -p -O qcow2 "$disk_path" "$output_file"

echo "Done."
