#!/bin/bash
set -euo pipefail

die() {
  echo "scrubs dirty exec: $*" >&2
  exit 1
}

write_exec_wrapper() {
  local target_path="$1"
  local wrapper_path="$2"

  mkdir -p "$(dirname "${wrapper_path}")"
  rm -f "${wrapper_path}"
  cat > "${wrapper_path}" << EOF
#!/bin/sh
exec '${target_path}' "\$@"
EOF
  chmod 755 "${wrapper_path}"
}

build_runtime_cache() {
  local cache_dir="$1"
  local cache_tmp_dir="${cache_dir}.tmp.$$"
  local cache_home="${cache_tmp_dir}/home"
  local cache_home_bin="${cache_home}/.local/share/scrubs-dirty/bin"
  local cache_mise_state_dir="${cache_home}/.local/state/mise"
  local spec
  local shim_name
  local resolved_shim_target

  rm -rf "${cache_tmp_dir}"
  mkdir -p \
    "${cache_home}/.config" \
    "${cache_home}/.local/bin" \
    "${cache_home}/.local/share" \
    "${cache_home}/.local/share/scrubs" \
    "${cache_home_bin}" \
    "${cache_mise_state_dir}"

  write_exec_wrapper /usr/bin/mise "${cache_home_bin}/mise"

  for spec in "${active_tool_specs[@]}"; do
    shim_name="${spec%%=*}"
    resolved_shim_target="${spec#*=}"
    write_exec_wrapper "${resolved_shim_target}" "${cache_home_bin}/${shim_name}"
  done

  cat > "${cache_home}/.gitconfig" << 'EOF'
[user]
  name = Scrubs Dirty
  email = dirty@example.invalid
[credential]
  helper =
EOF

  mv "${cache_tmp_dir}" "${cache_dir}"
}

build_helper_closure_cache() {
  local cache_file="$1"
  local cache_tmp_file="${cache_file}.tmp.$$"
  local helper_path
  local closure_path
  declare -A cache_seen_paths=()

  rm -f "${cache_tmp_file}"
  : > "${cache_tmp_file}"

  for helper_path in "${helper_input_paths[@]}"; do
    while IFS= read -r closure_path; do
      [[ -n "${closure_path}" ]] || continue
      if [[ -z "${cache_seen_paths["$closure_path"]+x}" ]]; then
        cache_seen_paths["$closure_path"]=1
        printf '%s\n' "${closure_path}" >> "${cache_tmp_file}"
      fi
    done < <("${NIX_STORE_BIN}" -qR "${helper_path}" 2> /dev/null)
  done

  mv "${cache_tmp_file}" "${cache_file}"
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
SCRUBS_DIR="${HOME}/.local/libexec/scrubs"
SANDBOX_DEFINITION="${SCRUBS_DIR}/sandbox-definition.sh"

[[ -x "${MISE_BIN}" ]] || die "missing clean mise binary at ${MISE_BIN}"
[[ -x "${BWRAP_BIN}" ]] || die "missing bubblewrap binary at ${BWRAP_BIN}"
[[ -x "${NIX_STORE_BIN}" ]] || die "missing nix-store binary at ${NIX_STORE_BIN}"
[[ -f "${SANDBOX_DEFINITION}" ]] || die "missing sandbox definition at ${SANDBOX_DEFINITION}"

# shellcheck source=/dev/null
source "${SANDBOX_DEFINITION}"

resolved_target="$("${MISE_BIN}" which "${command_name}" 2> /dev/null || true)"
[[ -n "${resolved_target}" ]] || die "${command_name} is not configured in mise for this directory"

current_user="$(id -un)"
helper_root="${HOME}/.local/share/scrubs/helper-root"
working_dir="$(pwd -P)"
project_root="$(git -C "$working_dir" rev-parse --show-toplevel 2> /dev/null || true)"
mise_root="${HOME}/.local/share/mise"
mise_shims="${mise_root}/shims"
mise_config_dir="${HOME}/.config/mise"
mise_state_dir="${HOME}/.local/state/mise"
runtime_cache_root="/tmp/scrubs-dirty-runtime-cache/${current_user}"
helper_closure_cache_root="/tmp/scrubs-helper-closure-cache/${current_user}"
node_modules_bin="${project_root}/node_modules/.bin"
ssl_cert_file="/etc/ssl/certs/ca-bundle.crt"
nix_ld="/run/current-system/sw/share/nix-ld/lib/ld.so"
nix_ld_library_path="/run/current-system/sw/share/nix-ld/lib"
guest_loader=""
runtime_cache_version="3"
helper_closure_cache_version="2"

for candidate_loader in /lib/ld-linux-aarch64.so.1 /lib64/ld-linux-x86-64.so.2; do
  if [[ -e "${candidate_loader}" ]]; then
    guest_loader="${candidate_loader}"
    break
  fi
done

[[ -d "${helper_root}" ]] || die "missing helper root at ${helper_root}"
[[ -d "${mise_root}" ]] || die "missing mise data directory at ${mise_root}"
[[ -d "${mise_config_dir}" ]] || die "missing mise config directory at ${mise_config_dir}"
[[ -n "${project_root}" ]] || die "dirty commands must run inside a git worktree"

declare -a active_tool_specs=()
if [[ -d "${mise_shims}" ]]; then
  while IFS= read -r shim_path; do
    shim_name="$(basename "${shim_path}")"
    [[ "${shim_name}" == "mise" ]] && continue
    resolved_shim_target="$("${MISE_BIN}" which "${shim_name}" 2> /dev/null || true)"
    [[ -n "${resolved_shim_target}" ]] || continue
    active_tool_specs+=("${shim_name}=${resolved_shim_target}")
  done < <(find "${mise_shims}" -maxdepth 1 -type l | sort)
fi

mkdir -p "${runtime_cache_root}" "${helper_closure_cache_root}" /tmp/mise-cache
chmod 700 "${runtime_cache_root}" "${helper_closure_cache_root}"

runtime_cache_key="$(
  printf '%s\n' \
    "${runtime_cache_version}" \
    "${project_root}" \
    "${active_tool_specs[@]}" \
    | cksum \
    | awk '{print $1 "-" $2}'
)"
runtime_cache_dir="${runtime_cache_root}/${runtime_cache_key}"
fake_home="${runtime_cache_dir}/home"

if [[ ! -x "${fake_home}/.local/share/scrubs-dirty/bin/mise" ]]; then
  build_runtime_cache "${runtime_cache_dir}"
fi

declare -a store_ro_binds=()
declare -A seen_store_paths=()
declare -a helper_input_paths=()
declare -a sandbox_dirs=()
declare -A seen_sandbox_dirs=()
declare -a extra_ro_binds=()
declare -a helper_file_binds=()

append_cached_store_path() {
  local closure_path="$1"

  [[ -n "${closure_path}" ]] || return 0
  if [[ -z "${seen_store_paths["$closure_path"]+x}" ]]; then
    seen_store_paths["$closure_path"]=1
    store_ro_binds+=(--ro-bind "$closure_path" "$closure_path")
  fi
}

collect_helper_input_if_present() {
  local helper_path="$1"
  local resolved_helper_path

  [[ -e "$helper_path" ]] || return 0
  resolved_helper_path="$(readlink -f "$helper_path")"
  [[ -n "${resolved_helper_path}" ]] || return 0
  helper_input_paths+=("${resolved_helper_path}")
}

append_sandbox_dir() {
  local dir_path="$1"

  [[ -n "${dir_path}" ]] || return 0
  if [[ -z "${seen_sandbox_dirs["$dir_path"]+x}" ]]; then
    seen_sandbox_dirs["$dir_path"]=1
    sandbox_dirs+=(--dir "${dir_path}")
  fi
}

append_parent_dirs() {
  local path_value="$1"
  local current_parent

  current_parent="$(dirname "${path_value}")"
  while [[ "${current_parent}" != "/" && "${current_parent}" != "." ]]; do
    append_sandbox_dir "${current_parent}"
    current_parent="$(dirname "${current_parent}")"
  done
}

if [[ -d "${helper_root}" ]]; then
  while IFS= read -r helper_entry; do
    collect_helper_input_if_present "${helper_entry}"
  done < <(find "${helper_root}" -mindepth 1 \( -type f -o -type l \) | sort)
fi

collect_helper_input_if_present "${guest_loader}"
collect_helper_input_if_present "${nix_ld}"
collect_helper_input_if_present "${nix_ld_library_path}"

helper_closure_cache_key="$(
  printf '%s\n' \
    "${helper_closure_cache_version}" \
    "${helper_input_paths[@]}" \
    | cksum \
    | awk '{print $1 "-" $2}'
)"
helper_closure_cache_file="${helper_closure_cache_root}/${helper_closure_cache_key}.paths"

if [[ ! -f "${helper_closure_cache_file}" ]]; then
  build_helper_closure_cache "${helper_closure_cache_file}"
fi

while IFS= read -r closure_path; do
  append_cached_store_path "${closure_path}"
done < "${helper_closure_cache_file}"

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
path_entries+=("/home/${current_user}/.local/share/scrubs-dirty/bin" "${mise_shims}" /bin /usr/bin)

dirty_path="$(
  IFS=:
  echo "${path_entries[*]}"
)"

declare -a mise_state_bind=()
if [[ -d "${mise_state_dir}" ]]; then
  mise_state_bind=(--ro-bind "${mise_state_dir}" "/home/${current_user}/.local/state/mise")
fi

for dir_path in "${SCRUBS_DIR_PATHS[@]}"; do
  append_sandbox_dir "${dir_path}"
done

for helper_file in "${SCRUBS_HELPER_COPY_FILES[@]}" "${SCRUBS_HELPER_LINK_FILES[@]}"; do
  [[ -e "${helper_root}${helper_file}" ]] || continue
  append_parent_dirs "${helper_file}"
  helper_file_binds+=(--ro-bind "${helper_root}${helper_file}" "${helper_file}")
done

for bind_path in "${SCRUBS_RO_BIND_PATHS[@]}"; do
  [[ -e "${bind_path}" ]] || continue
  if [[ -d "${bind_path}" ]]; then
    append_sandbox_dir "${bind_path}"
  else
    append_parent_dirs "${bind_path}"
  fi
  extra_ro_binds+=(--ro-bind "${bind_path}" "${bind_path}")
done

declare -a proc_bind=()
if [[ "${SCRUBS_ENABLE_PROC}" == "1" ]]; then
  proc_bind=(--proc /proc)
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
  --tmpfs / \
  "${proc_bind[@]}" \
  --dir /dev \
  --dev-bind /dev /dev \
  "${sandbox_dirs[@]}" \
  --dir "/home/${current_user}" \
  --ro-bind /lib /lib \
  --bind /tmp /tmp \
  --ro-bind "${helper_root}/bin" /bin \
  --ro-bind "${helper_root}/usr/bin" /usr/bin \
  "${helper_file_binds[@]}" \
  "${extra_ro_binds[@]}" \
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
