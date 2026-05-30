#!/bin/bash
set -euo pipefail

die() {
  echo "scrubs dirty exec: $*" >&2
  exit 1
}

write_exec_wrapper() {
  local target_path="$1"
  local wrapper_path="$2"

  rm -f "${wrapper_path}"
  cat > "${wrapper_path}" <<EOF
#!/bin/sh
exec '${target_path}' "\$@"
EOF
  chmod 755 "${wrapper_path}"
}

command_name="$(basename "$0")"
if [[ "$command_name" == "scrubs-dirty-exec" ]]; then
  [[ "$#" -gt 0 ]] || die "expected a command name"
  command_name="$1"
  shift
fi

MISE_BIN="/run/current-system/sw/bin/mise"
BWRAP_BIN="/run/current-system/sw/bin/bwrap"
NIX_STORE_BIN="/run/current-system/sw/bin/nix-store"

[[ -x "${MISE_BIN}" ]] || die "missing clean mise binary at ${MISE_BIN}"
[[ -x "${BWRAP_BIN}" ]] || die "missing bubblewrap binary at ${BWRAP_BIN}"
[[ -x "${NIX_STORE_BIN}" ]] || die "missing nix-store binary at ${NIX_STORE_BIN}"

resolved_target="$("${MISE_BIN}" which "${command_name}" 2>/dev/null || true)"
[[ -n "${resolved_target}" ]] || die "${command_name} is not configured in mise for this directory"

current_user="$(id -un)"
helper_root="${HOME}/.local/share/scrubs/helper-root"
fake_home="${HOME}/.local/share/scrubs/dirty-home"
fake_home_bin="${fake_home}/.local/bin"
fake_mise_state_dir="${fake_home}/.local/state/mise"
project_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd -P)"
working_dir="$(pwd -P)"
mise_root="${HOME}/.local/share/mise"
mise_shims="${mise_root}/shims"
mise_config_dir="${HOME}/.config/mise"
mise_state_dir="${HOME}/.local/state/mise"
node_modules_bin="${project_root}/node_modules/.bin"
ssl_cert_file="/etc/ssl/certs/ca-bundle.crt"
nix_ld="/run/current-system/sw/share/nix-ld/lib/ld.so"
nix_ld_library_path="/run/current-system/sw/share/nix-ld/lib"
guest_loader=""

for candidate_loader in /lib/ld-linux-aarch64.so.1 /lib64/ld-linux-x86-64.so.2; do
  if [[ -e "${candidate_loader}" ]]; then
    guest_loader="${candidate_loader}"
    break
  fi
done

[[ -d "${helper_root}" ]] || die "missing helper root at ${helper_root}"
[[ -d "${mise_root}" ]] || die "missing mise data directory at ${mise_root}"
[[ -d "${mise_config_dir}" ]] || die "missing mise config directory at ${mise_config_dir}"

mkdir -p \
  "${fake_home}/.config" \
  "${fake_home}/.local/share" \
  "${fake_home_bin}" \
  "${fake_mise_state_dir}" \
  /tmp/mise-cache

find "${fake_home_bin}" -mindepth 1 -maxdepth 1 -exec rm -f {} +

write_exec_wrapper /usr/bin/mise "${fake_home_bin}/mise"

if [[ -d "${mise_shims}" ]]; then
  while IFS= read -r shim_path; do
    shim_name="$(basename "${shim_path}")"
    [[ "${shim_name}" == "mise" ]] && continue
    resolved_shim_target="$("${MISE_BIN}" which "${shim_name}" 2>/dev/null || true)"
    [[ -n "${resolved_shim_target}" ]] || continue
    write_exec_wrapper "${resolved_shim_target}" "${fake_home_bin}/${shim_name}"
  done < <(find "${mise_shims}" -maxdepth 1 -type l | sort)
fi

cat > "${fake_home}/.gitconfig" <<'EOF'
[user]
  name = Scrubs Dirty
  email = dirty@example.invalid
[credential]
  helper =
EOF

declare -a store_ro_binds=()
declare -A seen_store_paths=()

append_store_closure() {
  local path="$1"
  local closure_path

  [[ -n "$path" && -e "$path" ]] || return 0

  while IFS= read -r closure_path; do
    [[ -n "${closure_path}" ]] || continue
    if [[ -z "${seen_store_paths["$closure_path"]+x}" ]]; then
      seen_store_paths["$closure_path"]=1
      store_ro_binds+=(--ro-bind "$closure_path" "$closure_path")
    fi
  done < <("${NIX_STORE_BIN}" -qR "$path" 2>/dev/null)
}

append_helper_if_present() {
  local helper_path="$1"

  [[ -e "$helper_path" ]] || return 0
  append_store_closure "$(readlink -f "$helper_path")"
}

append_helper_if_present "${helper_root}/bin/bash"
append_helper_if_present "${helper_root}/usr/bin/env"
append_helper_if_present "${helper_root}/usr/bin/git"
append_helper_if_present "${helper_root}/usr/bin/mise"
append_helper_if_present "${helper_root}/etc/ssl/certs/ca-bundle.crt"
append_helper_if_present "${guest_loader}"
append_helper_if_present "${nix_ld}"
append_helper_if_present "${nix_ld_library_path}"

resolved_nix_ld=""
resolved_nix_ld_library_path=""
if [[ -e "${nix_ld}" ]]; then
  resolved_nix_ld="$(readlink -f "${nix_ld}")"
fi
if [[ -e "${nix_ld_library_path}" ]]; then
  resolved_nix_ld_library_path="$(readlink -f "${nix_ld_library_path}")"
fi

declare -a path_entries=()
if [[ -d "${node_modules_bin}" ]]; then
  path_entries+=("${node_modules_bin}")
fi
path_entries+=("/home/${current_user}/.local/bin" "${mise_shims}" /bin /usr/bin)

dirty_path="$(IFS=:; echo "${path_entries[*]}")"

declare -a mise_state_bind=()
if [[ -d "${mise_state_dir}" ]]; then
  mise_state_bind=(--ro-bind "${mise_state_dir}" "/home/${current_user}/.local/state/mise")
fi

exec "${BWRAP_BIN}" \
  --die-with-parent \
  --new-session \
  --clearenv \
  --unshare-user \
  --unshare-ipc \
  --unshare-pid \
  --unshare-uts \
  --unshare-cgroup-try \
  --proc /proc \
  --tmpfs / \
  --dir /dev \
  --dev-bind /dev /dev \
  --dir /usr \
  --dir /etc \
  --dir /home \
  --dir "/home/${current_user}" \
  --dir /run \
  --dir /tmp \
  --ro-bind /lib /lib \
  --bind /tmp /tmp \
  --ro-bind "${helper_root}/bin" /bin \
  --ro-bind "${helper_root}/usr/bin" /usr/bin \
  --ro-bind "${helper_root}/etc/passwd" /etc/passwd \
  --ro-bind "${helper_root}/etc/group" /etc/group \
  --ro-bind "${helper_root}/etc/nsswitch.conf" /etc/nsswitch.conf \
  --ro-bind /etc/hosts /etc/hosts \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --bind "${fake_home}" "/home/${current_user}" \
  --ro-bind "${mise_root}" "/home/${current_user}/.local/share/mise" \
  --ro-bind "${mise_config_dir}" "/home/${current_user}/.config/mise" \
  --bind "${project_root}" "${project_root}" \
  --chdir "${working_dir}" \
  --setenv HOME "/home/${current_user}" \
  --setenv USER "${current_user}" \
  --setenv LOGNAME "${current_user}" \
  --setenv PATH "${dirty_path}" \
  --setenv PWD "${working_dir}" \
  --setenv SHELL /bin/sh \
  --setenv TMPDIR /tmp \
  --setenv MISE_DATA_DIR "/home/${current_user}/.local/share/mise" \
  --setenv MISE_CONFIG_DIR "/home/${current_user}/.config/mise" \
  --setenv MISE_CACHE_DIR /tmp/mise-cache \
  --setenv MISE_STATE_DIR "/home/${current_user}/.local/state/mise" \
  --setenv NIX_LD "${resolved_nix_ld}" \
  --setenv NIX_LD_LIBRARY_PATH "${resolved_nix_ld_library_path}" \
  --setenv SSL_CERT_FILE "${ssl_cert_file}" \
  "${mise_state_bind[@]}" \
  "${store_ro_binds[@]}" \
  -- \
  "${resolved_target}" "$@"
