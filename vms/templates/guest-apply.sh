#!/bin/sh
set -eu

payload="$HOME/scrubs-bootstrap"
bootstrap_marker="${SCRUBS_BOOTSTRAP_MARKER:-/var/lib/scrubs/bootstrap-complete}"
scrubs_nu="${SCRUBS_NU:-/run/current-system/sw/bin/nu}"
scrubs_nixos_rebuild="${SCRUBS_NIXOS_REBUILD:-nixos-rebuild}"
scrubs_hardware_config="${SCRUBS_HARDWARE_CONFIG:-/etc/nixos/hardware-configuration.nix}"
scrubs_state_dir="$HOME/.local/share/scrubs"
installed_manifest="$scrubs_state_dir/managed-home-paths.txt"
current_manifest="$payload/home/.local/share/scrubs/managed-home-paths.txt"

manifest_contains() {
  manifest_path="$1"
  managed_path="$2"
  [ -f "$manifest_path" ] || return 1
  grep -Fqx "$managed_path" "$manifest_path"
}

remove_managed_path() {
  managed_path="$1"
  [ -n "$managed_path" ] || return 0
  rm -rf "$HOME/$managed_path"
}

remove_stale_managed_paths() {
  previous_manifest="$1"
  next_manifest="$2"

  [ -f "$previous_manifest" ] || return 0

  while IFS= read -r managed_path || [ -n "$managed_path" ]; do
    [ -n "$managed_path" ] || continue

    if ! manifest_contains "$next_manifest" "$managed_path"; then
      remove_managed_path "$managed_path"
    fi
  done < "$previous_manifest"
}

converge_file() {
  src_path="$1"
  dst_path="$2"

  mkdir -p "$(dirname "$dst_path")"
  rm -f "$dst_path"
  cp "$src_path" "$dst_path"
}

converge_exact_dir() {
  src_dir="$1"
  dst_dir="$2"

  rm -rf "$dst_dir"

  if [ ! -d "$src_dir" ]; then
    return 0
  fi

  mkdir -p "$dst_dir"
  cp -R "$src_dir/." "$dst_dir/"
}

ensure_symlink() {
  target_path="$1"
  link_path="$2"

  mkdir -p "$(dirname "$link_path")"
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    ln -snf "$target_path" "$link_path"
  else
    rm -f "$link_path"
  fi
}

legacy_manifest="$(mktemp)"
cleanup_legacy_manifest() {
  rm -f "$legacy_manifest"
}
trap cleanup_legacy_manifest EXIT HUP INT TERM
cat > "$legacy_manifest" <<'EOF'
.gitconfig
.gitignore_global
.config/mise/config.toml
.config/nushell/carapace-init.nu
.config/nushell/config.nu
.config/nushell/config.shared.nu
.config/nushell/config.darwin.nu
.config/nushell/config.linux.nu
.config/nushell/env.nu
.config/nushell/env.shared.nu
.config/nushell/env.darwin.nu
.config/nushell/env.linux.nu
.config/nushell/kolo.nu
.config/nushell/mise.nu
.config/nushell/mise.darwin.nu
.config/nushell/ni-completions.nu
.config/nushell/vite-plus.nu
.local/bin/gh
.local/bin/codex
.local/libexec/scrubs
.local/share/scrubs/clean-auth
.profile
.bashrc
.bash_profile
EOF

if [ ! -f "$current_manifest" ]; then
  echo "scrubs bootstrap payload is missing managed-home-paths.txt" >&2
  exit 1
fi

mkdir -p "$HOME/.config/nushell" "$HOME/.config/mise" "$HOME/.local/bin" "$scrubs_state_dir"
chmod 700 "$scrubs_state_dir"

remove_stale_managed_paths "$legacy_manifest" "$current_manifest"
remove_stale_managed_paths "$installed_manifest" "$current_manifest"

converge_file "$payload/home/.gitconfig" "$HOME/.gitconfig"
converge_file "$payload/home/.gitignore_global" "$HOME/.gitignore_global"
converge_file "$payload/home/.config/mise/config.toml" "$HOME/.config/mise/config.toml"

for nushell_file in \
  carapace-init.nu \
  config.nu \
  config.shared.nu \
  config.linux.nu \
  env.nu \
  env.shared.nu \
  env.linux.nu \
  kolo.nu \
  ni-completions.nu \
  vite-plus.nu
do
  converge_file "$payload/home/.config/nushell/$nushell_file" "$HOME/.config/nushell/$nushell_file"
done

converge_exact_dir "$payload/home/.local/libexec/scrubs" "$HOME/.local/libexec/scrubs"
converge_exact_dir "$payload/home/.local/share/scrubs/clean-auth" "$HOME/.local/share/scrubs/clean-auth"

if [ -d "$HOME/.local/share/scrubs/clean-auth" ]; then
  chmod 700 "$HOME/.local/share/scrubs/clean-auth"
  find "$HOME/.local/share/scrubs/clean-auth" -type f -exec chmod 600 {} \;
fi

chmod 755 "$HOME/.local/libexec/scrubs/"*.sh
"$scrubs_nu" "$HOME/.local/libexec/scrubs/install-dirty-tools.nu"
ensure_symlink "$HOME/.local/libexec/scrubs/gh-clean.sh" "$HOME/.local/bin/gh"
ensure_symlink "$HOME/.local/libexec/scrubs/codex-clean.sh" "$HOME/.local/bin/codex"

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
converge_file "$payload/home/.profile" "$HOME/.profile"
converge_file "$payload/home/.bashrc" "$HOME/.bashrc"
converge_file "$payload/home/.bash_profile" "$HOME/.bash_profile"

cp "$current_manifest" "$installed_manifest"
chmod 600 "$installed_manifest"

cp "$scrubs_hardware_config" "$payload/scrubs/modules/runtime-hardware.nix"

if ! sudo -n true > /dev/null 2>&1; then
  echo "Guest user '__SCRUBS_BOOTSTRAP_USER__' needs passwordless sudo for bootstrap." >&2
  echo "Grant sudo in the base image or rerun manually inside the guest." >&2
  exit 1
fi

if sudo "$scrubs_nixos_rebuild" boot --flake "$payload/scrubs#scrubs-base"; then
  sudo install -d -m 755 "$(dirname "$bootstrap_marker")"
  sudo touch "$bootstrap_marker"
  exit 0
else
  exit "$?"
fi
