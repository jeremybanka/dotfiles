#!/bin/sh
set -eu

payload="$HOME/scrubs-bootstrap"

mkdir -p "$HOME/.config/nushell" "$HOME/.config/mise"
cp "$payload/home/.gitconfig" "$HOME/.gitconfig"
cp "$payload/home/.config/mise/config.toml" "$HOME/.config/mise/config.toml"
cp "$payload/home/.config/nushell/"* "$HOME/.config/nushell/"

mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"
if [ -f "$HOME/.gnupg/common.conf" ]; then
  grep -v '^use-keyboxd$' "$HOME/.gnupg/common.conf" > "$HOME/.gnupg/common.conf.tmp" || true
  mv "$HOME/.gnupg/common.conf.tmp" "$HOME/.gnupg/common.conf"
fi
gpgconf --kill keyboxd || true
rm -f "$HOME/.gnupg/public-keys.d/pubring.db.lock" "$HOME/.gnupg/public-keys.d"/.#lk* || true

if [ -f "$HOME/.bashrc" ] && ! grep -Fq 'SCRUBS_BASHRC' "$HOME/.bashrc"; then
  cp "$HOME/.bashrc" "$HOME/.bashrc.pre-scrubs"
fi
cp "$payload/home/.bashrc" "$HOME/.bashrc"
cp "$payload/home/.bash_profile" "$HOME/.bash_profile"

cp /etc/nixos/hardware-configuration.nix "$payload/scrubs/modules/runtime-hardware.nix"

if ! sudo -n true > /dev/null 2>&1; then
  echo "Guest user '__SCRUBS_BOOTSTRAP_USER__' needs passwordless sudo for bootstrap." >&2
  echo "Grant sudo in the base image or rerun manually inside the guest." >&2
  exit 1
fi

if sudo nixos-rebuild switch --flake "$payload/scrubs#scrubs-base"; then
  exit 0
else
  status=$?
fi

if [ "$status" -eq 4 ] && sudo systemctl is-failed --quiet cloud-final.service; then
  if sudo journalctl -u cloud-final.service -b --no-pager -n 120 | grep -Fq "Runparts: 1 failures"; then
    echo "cloud-final failed while introducing cloud-init into an older running guest." >&2
    echo "The new system is active; treating this one-time migration failure as non-fatal." >&2
    sudo systemctl reset-failed cloud-final.service || true
    exit 0
  fi
fi

exit "$status"
