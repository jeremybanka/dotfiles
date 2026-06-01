#!/bin/sh
set -eu

payload="$HOME/scrubs-bootstrap"
bootstrap_marker="/var/lib/scrubs/bootstrap-complete"

mkdir -p "$HOME/.config/nushell" "$HOME/.config/mise" "$HOME/.local/libexec/scrubs" "$HOME/.local/bin" "$HOME/.local/share/scrubs"
chmod 700 "$HOME/.local/share/scrubs"
cp "$payload/home/.gitconfig" "$HOME/.gitconfig"
cp "$payload/home/.gitignore_global" "$HOME/.gitignore_global"
cp "$payload/home/.config/mise/config.toml" "$HOME/.config/mise/config.toml"
cp "$payload/home/.config/nushell/"* "$HOME/.config/nushell/"
cp "$payload/home/.local/libexec/scrubs/"* "$HOME/.local/libexec/scrubs/"
if [ -d "$payload/home/.local/share/scrubs/clean-auth" ]; then
  mkdir -p "$HOME/.local/share/scrubs/clean-auth"
  cp -R "$payload/home/.local/share/scrubs/clean-auth/." "$HOME/.local/share/scrubs/clean-auth/"
  chmod 700 "$HOME/.local/share/scrubs/clean-auth"
  find "$HOME/.local/share/scrubs/clean-auth" -type f -exec chmod 600 {} \;
fi
chmod 755 "$HOME/.local/libexec/scrubs/"*.sh
"$HOME/.local/libexec/scrubs/install-dirty-tools.sh"
ln -snf "$HOME/.local/libexec/scrubs/gh-clean.sh" "$HOME/.local/bin/gh"
ln -snf "$HOME/.local/libexec/scrubs/codex-clean.sh" "$HOME/.local/bin/codex"

configure_github_git_helper() {
  gh_wrapper="$HOME/.local/bin/gh"
  github_helper_key="credential.https://github.com.helper"
  gist_helper_key="credential.https://gist.github.com.helper"

  git config --global --unset-all "$github_helper_key" || true
  git config --global --unset-all "$gist_helper_key" || true

  if [ ! -x "$gh_wrapper" ] || [ ! -f "$HOME/.local/share/scrubs/clean-auth/gh-token.enc" ]; then
    return 0
  fi

  git config --global --add "$github_helper_key" ""
  git config --global --add "$github_helper_key" "!$gh_wrapper auth git-credential"
  git config --global --add "$gist_helper_key" ""
  git config --global --add "$gist_helper_key" "!$gh_wrapper auth git-credential"
}

configure_github_git_helper

is_legacy_scrubs_bashrc() {
  file_path="$1"
  [ -f "$file_path" ] || return 1
  grep -Fq 'SCRUBS_BASHRC' "$file_path" && return 1
  grep -Fq 'if [ -f "$HOME/.bashrc.pre-scrubs" ]; then' "$file_path" || return 1
  grep -Fq 'PATH="$HOME/.local/bin:$PATH"' "$file_path" || return 1
}

mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"
if [ -f "$HOME/.gnupg/common.conf" ]; then
  grep -v '^use-keyboxd$' "$HOME/.gnupg/common.conf" > "$HOME/.gnupg/common.conf.tmp" || true
  mv "$HOME/.gnupg/common.conf.tmp" "$HOME/.gnupg/common.conf"
fi
gpgconf --kill keyboxd || true
rm -f "$HOME/.gnupg/public-keys.d/pubring.db.lock" "$HOME/.gnupg/public-keys.d"/.#lk* || true

if is_legacy_scrubs_bashrc "$HOME/.bashrc.pre-scrubs"; then
  rm -f "$HOME/.bashrc.pre-scrubs"
fi

if [ -f "$HOME/.bashrc" ] \
  && ! grep -Fq 'SCRUBS_BASHRC' "$HOME/.bashrc" \
  && ! is_legacy_scrubs_bashrc "$HOME/.bashrc"; then
  cp "$HOME/.bashrc" "$HOME/.bashrc.pre-scrubs"
fi
if [ -f "$HOME/.profile" ] && ! grep -Fq 'SCRUBS_PROFILE' "$HOME/.profile"; then
  cp "$HOME/.profile" "$HOME/.profile.pre-scrubs"
fi
cp "$payload/home/.profile" "$HOME/.profile"
cp "$payload/home/.bashrc" "$HOME/.bashrc"
cp "$payload/home/.bash_profile" "$HOME/.bash_profile"

cp /etc/nixos/hardware-configuration.nix "$payload/scrubs/modules/runtime-hardware.nix"

if ! sudo -n true > /dev/null 2>&1; then
  echo "Guest user '__SCRUBS_BOOTSTRAP_USER__' needs passwordless sudo for bootstrap." >&2
  echo "Grant sudo in the base image or rerun manually inside the guest." >&2
  exit 1
fi

if sudo test -f "$bootstrap_marker"; then
  if sudo nixos-rebuild boot --flake "$payload/scrubs#scrubs-base"; then
    exit 0
  else
    exit "$?"
  fi
fi

if sudo nixos-rebuild switch --flake "$payload/scrubs#scrubs-base"; then
  sudo install -d -m 755 "$(dirname "$bootstrap_marker")"
  sudo touch "$bootstrap_marker"
  exit 0
else
  status=$?
fi

if [ "$status" -eq 4 ] && sudo systemctl is-failed --quiet cloud-final.service; then
  if sudo journalctl -u cloud-final.service -b --no-pager -n 120 | grep -Fq "Runparts: 1 failures"; then
    echo "cloud-final failed while introducing cloud-init into an older running guest." >&2
    echo "The new system is active; treating this one-time migration failure as non-fatal." >&2
    sudo install -d -m 755 "$(dirname "$bootstrap_marker")"
    sudo touch "$bootstrap_marker"
    sudo systemctl reset-failed cloud-final.service || true
    exit 0
  fi
fi

exit "$status"
