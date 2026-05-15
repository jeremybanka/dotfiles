#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
scrubs_dir="$repo_root/lima/nixos"
cache_dir="${TMPDIR:-/tmp}/scrubs-lima"
instance_name="${1:-scrubs-dev}"
settings_file="$scrubs_dir/settings.env"
template_file="$scrubs_dir/lima.local.yaml"
payload_dir="$cache_dir/scrubs-bootstrap"
guest_apply="$payload_dir/guest-apply.sh"
current_user=$(id -un)
current_uid=$(id -u)
guest_user="${SCRUBS_GUEST_USER:-$current_user}"
guest_uid="${SCRUBS_GUEST_UID:-$current_uid}"
bootstrap_user="${SCRUBS_BOOTSTRAP_USER:-$guest_user}"
bootstrap_home="/home/$bootstrap_user"
base_image="${SCRUBS_BASE_IMAGE:-}"
guest_arch="${SCRUBS_ARCH:-aarch64}"
key_dir="$scrubs_dir/keys"
key_path="$key_dir/scrubs-dev"
start_timeout="${SCRUBS_START_TIMEOUT:-90s}"
ssh_port="${SCRUBS_SSH_PORT:-}"
host_port_3000="${SCRUBS_HOST_PORT_3000:-}"
host_port_5173="${SCRUBS_HOST_PORT_5173:-}"
host_port_8080="${SCRUBS_HOST_PORT_8080:-}"

if [ -f "$settings_file" ]; then
  # shellcheck disable=SC1090
  . "$settings_file"
fi

if [ -z "${SCRUBS_BASE_IMAGE:-$base_image}" ]; then
  echo "Set SCRUBS_BASE_IMAGE in the environment or lima/nixos/settings.env." >&2
  echo "Use an OpenStack-compatible NixOS image with cloud-init support." >&2
  exit 1
fi

base_image="${SCRUBS_BASE_IMAGE:-$base_image}"
guest_user="${SCRUBS_GUEST_USER:-$guest_user}"
guest_uid="${SCRUBS_GUEST_UID:-$guest_uid}"
bootstrap_user="${SCRUBS_BOOTSTRAP_USER:-$bootstrap_user}"
bootstrap_home="/home/$bootstrap_user"
guest_arch="${SCRUBS_ARCH:-$guest_arch}"
ssh_port="${SCRUBS_SSH_PORT:-$ssh_port}"
host_port_3000="${SCRUBS_HOST_PORT_3000:-$host_port_3000}"
host_port_5173="${SCRUBS_HOST_PORT_5173:-$host_port_5173}"
host_port_8080="${SCRUBS_HOST_PORT_8080:-$host_port_8080}"

if [ -z "$ssh_port" ] || [ -z "$host_port_3000" ] || [ -z "$host_port_5173" ] || [ -z "$host_port_8080" ]; then
  if [ "$instance_name" = "scrubs-dev" ]; then
    port_offset=0
  else
    instance_hash=$(printf '%s\n' "$instance_name" | cksum | awk '{print $1}')
    port_offset=$((instance_hash % 1000 + 1))
  fi
fi

ssh_port="${ssh_port:-$((60022 + port_offset))}"
host_port_3000="${host_port_3000:-$((3000 + port_offset))}"
host_port_5173="${host_port_5173:-$((5173 + port_offset))}"
host_port_8080="${host_port_8080:-$((8080 + port_offset))}"

case "$guest_arch" in
  aarch64|x86_64) ;;
  *)
    echo "Unsupported SCRUBS_ARCH: $guest_arch" >&2
    echo "Use aarch64 or x86_64." >&2
    exit 1
    ;;
esac

rm -rf "$payload_dir"
mkdir -p "$cache_dir" "$key_dir" "$payload_dir/home/.config/nushell" "$payload_dir/home/.config/mise" "$payload_dir/lima/nixos/modules"

if [ ! -f "$key_path" ]; then
  ssh-keygen -t ed25519 -N "" -f "$key_path" >/dev/null
fi

if printf '%s' "$base_image" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://'; then
  image_location="$base_image"
else
  image_location=$(cd "$(dirname "$base_image")" && pwd)/$(basename "$base_image")
  if [ ! -f "$image_location" ]; then
    echo "Base image not found: $image_location" >&2
    exit 1
  fi
fi

cp "$repo_root/home/.gitconfig" "$payload_dir/home/.gitconfig"
cp "$repo_root/home/.config/mise/config.toml" "$payload_dir/home/.config/mise/config.toml"
cp "$repo_root/home/.config/nushell/config.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/config.shared.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/config.darwin.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/config.linux.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/env.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/env.shared.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/env.darwin.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/env.linux.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/kolo.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/mise.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/ni-completions.nu" "$payload_dir/home/.config/nushell/"
cp "$repo_root/home/.config/nushell/vite-plus.nu" "$payload_dir/home/.config/nushell/"

cp "$scrubs_dir/flake.nix" "$payload_dir/lima/nixos/flake.nix"
cp "$scrubs_dir/flake.lock" "$payload_dir/lima/nixos/flake.lock"
cp "$scrubs_dir/configuration.nix" "$payload_dir/lima/nixos/configuration.nix"
cp "$scrubs_dir/modules/base.nix" "$payload_dir/lima/nixos/modules/base.nix"

repo_pubkey=$(cat "$key_path.pub")

cat > "$payload_dir/lima/nixos/modules/guest-user.nix" <<EOF
{ pkgs, ... }:
{
  users.users = {
    "${guest_user}" = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.nushell;
      openssh.authorizedKeys.keys = [
        "${repo_pubkey}"
      ];
    };
  };
}
EOF

cat > "$guest_apply" <<EOF
#!/bin/sh
set -eu

payload="\$HOME/scrubs-bootstrap"

mkdir -p "\$HOME/.config/nushell" "\$HOME/.config/mise"
cp "\$payload/home/.gitconfig" "\$HOME/.gitconfig"
cp "\$payload/home/.config/mise/config.toml" "\$HOME/.config/mise/config.toml"
cp "\$payload/home/.config/nushell/"* "\$HOME/.config/nushell/"
cp /etc/nixos/hardware-configuration.nix "\$payload/lima/nixos/modules/runtime-hardware.nix"

if ! sudo -n true >/dev/null 2>&1; then
  echo "Guest user '$bootstrap_user' needs passwordless sudo for bootstrap." >&2
  echo "Grant sudo in the base image or rerun manually inside the guest." >&2
  exit 1
fi

sudo nixos-rebuild switch --flake "\$payload/lima/nixos#scrubs-base"
EOF

chmod +x "$guest_apply"

escaped_image_location=$(printf '%s\n' "$image_location" | sed 's/[&|]/\\&/g')
escaped_guest_user=$(printf '%s\n' "$guest_user" | sed 's/[&|]/\\&/g')
escaped_guest_uid=$(printf '%s\n' "$guest_uid" | sed 's/[&|]/\\&/g')
escaped_guest_arch=$(printf '%s\n' "$guest_arch" | sed 's/[&|]/\\&/g')
escaped_ssh_port=$(printf '%s\n' "$ssh_port" | sed 's/[&|]/\\&/g')
escaped_host_port_3000=$(printf '%s\n' "$host_port_3000" | sed 's/[&|]/\\&/g')
escaped_host_port_5173=$(printf '%s\n' "$host_port_5173" | sed 's/[&|]/\\&/g')
escaped_host_port_8080=$(printf '%s\n' "$host_port_8080" | sed 's/[&|]/\\&/g')
sed \
  -e "s|REPLACE_WITH_BASE_IMAGE|$escaped_image_location|g" \
  -e "s|REPLACE_WITH_GUEST_USER|$escaped_guest_user|g" \
  -e "s|REPLACE_WITH_GUEST_UID|$escaped_guest_uid|g" \
  -e "s|REPLACE_WITH_ARCH|$escaped_guest_arch|g" \
  -e "s|REPLACE_WITH_SSH_PORT|$escaped_ssh_port|g" \
  -e "s|REPLACE_WITH_HOST_PORT_3000|$escaped_host_port_3000|g" \
  -e "s|REPLACE_WITH_HOST_PORT_5173|$escaped_host_port_5173|g" \
  -e "s|REPLACE_WITH_HOST_PORT_8080|$escaped_host_port_8080|g" \
  "$scrubs_dir/lima.yaml" > "$template_file"

echo "Starting Lima instance $instance_name"
if ! limactl start --containerd=none --timeout="$start_timeout" --name="$instance_name" "$template_file"; then
  echo "limactl start did not fully complete within $start_timeout." >&2
  echo "Continuing because scrubs only requires SSH reachability for bootstrap." >&2
fi

echo "Waiting for SSH access to the guest"
ready=0
i=0
while [ "$i" -lt 60 ]; do
  if limactl shell "$instance_name" true >/dev/null 2>&1; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 2
done

if [ "$ready" -ne 1 ]; then
  echo "Guest did not become reachable over SSH in time." >&2
  exit 1
fi

echo "Copying scrubs payload into the guest"
limactl shell "$instance_name" rm -rf "$bootstrap_home/scrubs-bootstrap"
limactl shell "$instance_name" mkdir -p "$bootstrap_home/scrubs-bootstrap"
limactl copy --backend=scp -r "$payload_dir/." "$instance_name:$bootstrap_home/scrubs-bootstrap/"

echo "Applying scrubs base configuration inside the guest"
limactl shell "$instance_name" sh "$bootstrap_home/scrubs-bootstrap/guest-apply.sh"

echo "Scrubs guest is ready."
echo "Use: limactl shell $instance_name"
