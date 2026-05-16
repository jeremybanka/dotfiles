#!/bin/sh
set -eu

channel="${1:-${SCRUBS_SEED_CHANNEL:-nixos-25.11}}"
arch="${SCRUBS_SEED_ARCH:-aarch64}"
flavor="${SCRUBS_SEED_FLAVOR:-minimal}"
cache_dir="${SCRUBS_ISO_CACHE_DIR:-$HOME/Library/Caches/scrubs}"

case "$arch" in
  aarch64|x86_64) ;;
  *)
    echo "Unsupported architecture: $arch" >&2
    echo "Use aarch64 or x86_64." >&2
    exit 1
    ;;
esac

case "$flavor" in
  minimal|graphical) ;;
  *)
    echo "Unsupported ISO flavor: $flavor" >&2
    echo "Use minimal or graphical." >&2
    exit 1
    ;;
esac

mkdir -p "$cache_dir"

latest_url="https://channels.nixos.org/$channel/latest-nixos-$flavor-$arch-linux.iso"
file_name="nixos-$channel-latest-$flavor-$arch-linux.iso"
output_path="$cache_dir/$file_name"
resolved_url_file="$output_path.source-url"
sha256_file="$output_path.sha256"

echo "Downloading $latest_url"
curl --fail --location --continue-at - --output "$output_path" "$latest_url"

resolved_url=$(curl --silent --show-error --location --output /dev/null --write-out '%{url_effective}' "$latest_url")
printf '%s\n' "$resolved_url" > "$resolved_url_file"

sha256=$(shasum -a 256 "$output_path" | awk '{print $1}')
printf '%s  %s\n' "$sha256" "$(basename "$output_path")" > "$sha256_file"

echo "Saved ISO to $output_path"
echo "Resolved release URL: $resolved_url"
echo "Local SHA-256: $sha256"
echo "Metadata:"
echo "  $resolved_url_file"
echo "  $sha256_file"
