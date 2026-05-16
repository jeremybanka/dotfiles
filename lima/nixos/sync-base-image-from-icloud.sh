#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
local_dir="${SCRUBS_LOCAL_BASE_IMAGE_DIR:-$repo_root/lima/nixos/qcow2}"
icloud_dir="${SCRUBS_ICLOUD_BASE_IMAGE_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/scrubs/base-images}"
image_name="${1:-scrubs-linux-lts.qcow2}"
source_path="$icloud_dir/$image_name"
dest_path="$local_dir/$image_name"

if [ ! -f "$source_path" ]; then
  echo "iCloud base image not found: $source_path" >&2
  exit 1
fi

mkdir -p "$local_dir"
cp -f "$source_path" "$dest_path"

echo "Copied $source_path"
echo "to $dest_path"
