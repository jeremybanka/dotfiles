#!/bin/bash
set -euo pipefail

# Project command proxies must never influence clean sandbox construction.
export PATH=/run/current-system/sw/bin:/run/wrappers/bin

die() {
  echo "scrubs dirty exec: $*" >&2
  exit 1
}

# Task-cache override is deliberately one reserved directory, not an arbitrary
# writable bind. It stays inside the already-authorized project mount.
configure_task_cache() {
  [[ -n "${SCRUBS_DIRTY_CACHE_ROOT:-}" ]] || return 0
  [[ -n "${project_root}" && "${project_root}" == /* ]] || die "task cache requires a git worktree"
  local expected="${project_root}/.scrubs-dirty-cache"
  [[ "${SCRUBS_DIRTY_CACHE_ROOT}" == "${expected}" ]] || die "task cache must be ${expected}"
  local suffix target
  # Refuse redirected or foreign-owned cache directories before chmod/mkdir.
  for suffix in "" /mise /bun /bun/install /bun/install/cache; do
    target="${expected}${suffix}"
    [[ ! -L "${target}" ]] || die "task cache directory must not be a symlink: ${target}"
    if [[ -e "${target}" ]]; then
      [[ -d "${target}" && -O "${target}" ]] || die "task cache directory must be owned by this user: ${target}"
    fi
  done
  dirty_cache_root="${expected}"
  mise_cache_root="${expected}/mise"
}
# End task-cache validation.

# Only clean policy can authorize a common Git metadata directory. A worktree's
# .git indirection is not authority to expose an arbitrary host path.
append_readonly_git_metadata() {
  local common gitdir approved root path rel backlink
  approved=0
  for root in "${SCRUBS_GIT_METADATA_WORKTREES[@]}"; do
    [[ "${root}" == /* && "${root}" != / && ! -L "${root}" ]] || die "invalid clean Git metadata worktree"
    [[ "$(realpath "${root}")" == "${root}" ]] || die "Git metadata worktree must be canonical"
    [[ "${project_root}" == "${root}" ]] && approved=1
  done
  [[ "${approved}" == 1 ]] || return 0
  [[ -f "${project_root}/.git" && ! -L "${project_root}/.git" ]] || return 0
  common="$(git -C "${project_root}" rev-parse --path-format=absolute --git-common-dir)" || die "cannot resolve Git common directory"
  gitdir="$(git -C "${project_root}" rev-parse --absolute-git-dir)" || die "cannot resolve Git worktree directory"
  approved=0
  for root in "${SCRUBS_GIT_METADATA_ROOTS[@]}"; do
    [[ "${root}" == /* && "${root}" != / && ! -L "${root}" ]] || die "invalid clean Git metadata root"
    [[ "$(realpath "${root}")" == "${root}" ]] || die "Git metadata root must be canonical"
    [[ "${common}" == "${root}" ]] && approved=1
  done
  [[ "${approved}" == 1 ]] || return 0
  [[ "${gitdir}" == "${common}/worktrees/"* ]] || die "Git worktree metadata is outside its authorized root"
  rel="${gitdir#"${common}/worktrees/"}"
  [[ -n "${rel}" && "${rel}" != */* && ! -L "${gitdir}" ]] || die "invalid Git worktree slot"
  [[ "$(realpath "${gitdir}")" == "${gitdir}" ]] || die "Git worktree slot must be canonical"
  backlink="$(cat "${gitdir}/gitdir")"
  [[ "${backlink}" == "${project_root}/.git" ]] || die "Git worktree backlink mismatch"
  git_metadata_binds+=(--dir "${common}" --dir "${gitdir}")
  # Deliberately omit config, hooks, logs and all other worktree slots. Objects
  # and refs provide history/baselines; index supports read-only diff/status.
  for path in "${common}"/{HEAD,objects,refs,packed-refs,shallow} "${gitdir}"/{HEAD,commondir,gitdir,index}; do
    [[ ! -L "${path}" ]] || die "Git metadata entry must not be a symlink: ${path}"
    [[ -e "${path}" ]] || continue
    git_metadata_binds+=(--ro-bind "${path}" "${path}")
  done
}
# End read-only Git metadata selection.

# Clean policy grants library directories to exact canonical task roots only.
append_task_libraries() {
  local root path approved=0 search=""
  for root in "${SCRUBS_TASK_LIBRARY_WORKTREES[@]}"; do
    [[ "${root}" == /* && "${root}" != / && ! -L "${root}" ]] || die "invalid task library worktree"
    [[ "$(realpath "${root}")" == "${root}" ]] || die "task library worktree must be canonical"
    [[ "${project_root}" == "${root}" ]] && approved=1
  done
  [[ "${approved}" == 1 ]] || return 0
  for path in "${SCRUBS_TASK_LIBRARY_PATHS[@]}"; do
    [[ "${path}" =~ ^/nix/store/[a-z0-9]{32}-[^/]+/lib(64)?$ ]] || die "task libraries must be Nix store library directories"
    [[ -d "${path}" && ! -L "${path}" && "$(realpath "${path}")" == "${path}" ]] || die "task library directory must be canonical"
    task_library_binds+=(--ro-bind "${path}" "${path}")
    search="${search:+${search}:}${path}"
  done
  for path in "${SCRUBS_TASK_FONT_PATHS[@]}"; do
    [[ "${path}" =~ ^/nix/store/[a-z0-9]{32}-[^/]+/share/fonts$ ]] || die "task fonts must be Nix store font directories"
    [[ -d "${path}" && ! -L "${path}" && "$(realpath "${path}")" == "${path}" ]] || die "task font directory must be canonical"
    task_library_binds+=(--ro-bind "${path}" "${path}")
  done
  [[ -z "${search}" ]] || task_library_env+=(--setenv LD_LIBRARY_PATH "${search}")
}
# End task library selection.

resolve_host_command_path() {
  local command_name="$1"
  local resolved

  if [[ -x "/run/current-system/sw/bin/${command_name}" ]]; then
    resolved="/run/current-system/sw/bin/${command_name}"
  else
    resolved="$(command -v "${command_name}" 2> /dev/null || true)"
  fi

  [[ -n "${resolved}" ]] || return 1
  readlink -f "${resolved}"
}

resolve_mise_target() {
  local command_name="$1"

  env \
    RUSTUP_HOME="${scrubs_rustup_home}" \
    CARGO_HOME="${scrubs_rust_bootstrap_cargo_home}" \
    "${MISE_BIN}" which "${command_name}" 2> /dev/null || true
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

write_bun_wrapper() {
  local target_path="$1"
  local wrapper_path="$2"

  mkdir -p "$(dirname "${wrapper_path}")"
  rm -f "${wrapper_path}"
  cat > "${wrapper_path}" << EOF
#!/bin/sh
# Bun 1.4.0 can strand its default 48 concurrent package requests in Linux
# guests. Apply the measured-safe default to installs launched anywhere inside
# dirty space, while preserving an explicit caller override.
case "\${1:-}" in
  install|i)
    for arg in "\$@"; do
      case "\${arg}" in
        --network-concurrency|--network-concurrency=*)
          exec '${target_path}' "\$@"
          ;;
      esac
    done

    subcommand="\$1"
    shift
    exec '${target_path}' "\${subcommand}" --network-concurrency=${bun_install_network_concurrency} "\$@"
    ;;
esac

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
    "${cache_home}/.bun/install/cache" \
    "${cache_home}/.cargo" \
    "${cache_home}/.local/bin" \
    "${cache_home}/.local/share" \
    "${cache_home}/.local/share/scrubs" \
    "${cache_home_bin}" \
    "${cache_mise_state_dir}"

  if [[ -n "${active_aube_store}" && "${active_aube_store}" == "${HOME}/"* ]]; then
    mkdir -p "${cache_home}/${active_aube_store#"${HOME}/"}"
  fi

  write_exec_wrapper /usr/bin/mise "${cache_home_bin}/mise"

  for spec in "${runtime_wrapper_specs[@]}"; do
    shim_name="${spec%%=*}"
    resolved_shim_target="${spec#*=}"
    if [[ "${shim_name}" == "bun" ]]; then
      write_bun_wrapper "${resolved_shim_target}" "${cache_home_bin}/${shim_name}"
    else
      write_exec_wrapper "${resolved_shim_target}" "${cache_home_bin}/${shim_name}"
    fi
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

local_node=0
if [[ "$(basename "$0")" == "dirty-exec.sh" && "${1:-}" == "--local-node" ]]; then
  local_node=1
  shift
  [[ "$#" -gt 0 ]] || die "expected a local command name"
  command_name="$1"
  shift
  case "$command_name" in
    git | gh | claude | codex | nu | carapace | mise | scrubs-dirty-exec | comline-completion) die "reserved clean command: $command_name" ;;
  esac
  [[ "$command_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]] || die "invalid local command name"
  if [[ -e "/run/current-system/sw/bin/$command_name" || -e "/run/wrappers/bin/$command_name" ]]; then
    die "reserved clean command: $command_name"
  fi
else
  command_name="$(basename "$0")"
  if [[ "$command_name" == "scrubs-dirty-exec" ]]; then
    [[ "$#" -gt 0 ]] || die "expected a command name"
    command_name="$1"
    shift
  fi
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
SCRUBS_GIT_METADATA_ROOTS=()
SCRUBS_GIT_METADATA_WORKTREES=()
SCRUBS_TASK_LIBRARY_WORKTREES=()
SCRUBS_TASK_LIBRARY_PATHS=()
SCRUBS_TASK_FONT_PATHS=()
source "${SANDBOX_DEFINITION}"

current_user="$(id -un)"
helper_root="${HOME}/.local/share/scrubs/helper-root"
working_dir="$(pwd -P)"
project_root="$(git -C "$working_dir" rev-parse --show-toplevel 2> /dev/null || true)"
mise_root="${HOME}/.local/share/mise"
mise_shims="${mise_root}/shims"
mise_config_dir="${HOME}/.config/mise"
mise_state_dir="${HOME}/.local/state/mise"
# Embedded Aube leaves mise package links pointing into this materialized
# package tree. Expose only that exact subtree, never the surrounding cache.
xdg_cache_home="${XDG_CACHE_HOME:-}"
if [[ -z "${xdg_cache_home}" || "${xdg_cache_home}" != /* ]]; then
  xdg_cache_home="${HOME}/.cache"
fi
if [[ "${xdg_cache_home}" == "/" ]]; then
  aube_store="/aube/virtual-store"
else
  aube_store="${xdg_cache_home%/}/aube/virtual-store"
fi
active_aube_store=""
if [[ -d "${aube_store}" ]]; then
  active_aube_store="${aube_store}"
fi
scrubs_rustup_home="${mise_root}/rustup-home"
scrubs_rust_bootstrap_cargo_home="${mise_root}/rust-cargo-home"
runtime_cache_root="/tmp/scrubs-dirty-runtime-cache/${current_user}"
helper_closure_cache_root="/tmp/scrubs-helper-closure-cache/${current_user}"
# Persist only Bun's package payload cache across synthetic-home/runtime-key
# changes. The surrounding real home remains outside the dirty boundary.
dirty_cache_root="${HOME}/.local/share/scrubs/dirty-cache"
mise_cache_root="/tmp/mise-cache"
configure_task_cache
bun_install_cache="${dirty_cache_root}/bun/install/cache"
bun_install_network_concurrency="8"
node_modules_bin=""
if [[ -n "${project_root}" ]]; then
  node_modules_bin="$(/run/current-system/sw/bin/nu --no-config-file "${HOME}/.config/nushell/local-node-path.nu" "$working_dir" --root "$project_root")"
fi
ssl_cert_file="/etc/ssl/certs/ca-bundle.crt"
nix_ld="/run/current-system/sw/share/nix-ld/lib/ld.so"
nix_ld_library_path="/run/current-system/sw/share/nix-ld/lib"
guest_loader=""
runtime_cache_version="6"
helper_closure_cache_version="2"

if [[ "$local_node" == "1" ]]; then
  [[ -n "$node_modules_bin" ]] || die "no local node_modules/.bin in this worktree"
  resolved_target="${node_modules_bin}/${command_name}"
  [[ -f "$resolved_target" && -x "$resolved_target" ]] || die "local command is missing or not executable: ${command_name}"
  case "$(readlink -f "$resolved_target")" in
    "${project_root}/"*) ;;
    *) die "local command resolves outside this worktree" ;;
  esac
else
  resolved_target="$(resolve_mise_target "${command_name}")"
  [[ -n "${resolved_target}" ]] || die "${command_name} is not configured in mise for this directory"
fi

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
    resolved_shim_target="$(resolve_mise_target "${shim_name}")"
    [[ -n "${resolved_shim_target}" ]] || continue
    active_tool_specs+=("${shim_name}=${resolved_shim_target}")
  done < <(find "${mise_shims}" -maxdepth 1 -type l | sort)
fi

rust_tooling_active=0
for spec in "${active_tool_specs[@]}"; do
  resolved_shim_target="${spec#*=}"
  if [[ "${resolved_shim_target}" == "${scrubs_rust_bootstrap_cargo_home}/"* ]]; then
    rust_tooling_active=1
    break
  fi
done

declare -a extra_dirty_wrapper_specs=()
if [[ "${rust_tooling_active}" == "1" ]]; then
  resolved_shim_target="$(resolve_host_command_path "cc" 2> /dev/null || true)"
  [[ -n "${resolved_shim_target}" ]] && extra_dirty_wrapper_specs+=("cc=${resolved_shim_target}")
fi

declare -a runtime_wrapper_specs=(
  "${active_tool_specs[@]}"
  "${extra_dirty_wrapper_specs[@]}"
)

mkdir -p \
  "${runtime_cache_root}" \
  "${helper_closure_cache_root}" \
  "${bun_install_cache}" \
  "${mise_cache_root}"
chmod 700 "${runtime_cache_root}" "${helper_closure_cache_root}"
chmod 700 \
  "${dirty_cache_root}" \
  "${dirty_cache_root}/bun" \
  "${dirty_cache_root}/bun/install" \
  "${bun_install_cache}"

runtime_cache_key="$(
  printf '%s\n' \
    "${runtime_cache_version}" \
    "${project_root}" \
    "${active_aube_store}" \
    "${runtime_wrapper_specs[@]}" \
    | cksum \
    | awk '{print $1 "-" $2}'
)"
runtime_cache_dir="${runtime_cache_root}/${runtime_cache_key}"
fake_home="${runtime_cache_dir}/home"

if [[ ! -x "${fake_home}/.local/share/scrubs-dirty/bin/mise" ]]; then
  build_runtime_cache "${runtime_cache_dir}"
fi

sandbox_target="${resolved_target}"
if [[ "${command_name}" == "bun" && "$local_node" == "0" ]]; then
  sandbox_target="/home/${current_user}/.local/share/scrubs-dirty/bin/bun"
fi

declare -a store_ro_binds=()
declare -A seen_store_paths=()
declare -a helper_input_paths=()
declare -a sandbox_dirs=()
declare -A seen_sandbox_dirs=()
declare -a extra_ro_binds=()
declare -a git_metadata_binds=()
append_readonly_git_metadata
declare -a task_library_binds=()
declare -a task_library_env=()
append_task_libraries
declare -a helper_file_binds=()
declare -a aube_store_bind=()

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

if [[ -n "${active_aube_store}" ]]; then
  if [[ "${active_aube_store}" != "${HOME}/"* ]]; then
    append_parent_dirs "${active_aube_store}"
    append_sandbox_dir "${active_aube_store}"
  fi
  aube_store_bind=(--ro-bind "${active_aube_store}" "${active_aube_store}")
fi

if [[ -d "${helper_root}" ]]; then
  while IFS= read -r helper_entry; do
    collect_helper_input_if_present "${helper_entry}"
  done < <(find "${helper_root}" -mindepth 1 \( -type f -o -type l \) | sort)
fi

for spec in "${extra_dirty_wrapper_specs[@]}"; do
  collect_helper_input_if_present "${spec#*=}"
done

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

if [[ ! -s "${helper_closure_cache_file}" ]]; then
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

if [[ -n "${resolved_nix_ld}" ]]; then
  append_parent_dirs "${nix_ld}"
  extra_ro_binds+=(--ro-bind "${resolved_nix_ld}" "${nix_ld}")
fi

if [[ -n "${resolved_nix_ld_library_path}" ]]; then
  append_parent_dirs "${nix_ld_library_path}"
  extra_ro_binds+=(--ro-bind "${resolved_nix_ld_library_path}" "${nix_ld_library_path}")
fi

declare -a proc_bind=()
if [[ "${SCRUBS_ENABLE_PROC}" == "1" ]]; then
  proc_bind=(--proc /proc)
fi

declare -a terminal_env_args=()
for env_name in TERM COLORTERM NO_COLOR NODE_DISABLE_COLORS FORCE_COLOR; do
  if [[ "${!env_name+x}" == "x" ]]; then
    terminal_env_args+=(--setenv "${env_name}" "${!env_name}")
  fi
done

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
  --bind "${bun_install_cache}" "/home/${current_user}/.bun/install/cache" \
  "${aube_store_bind[@]}" \
  --ro-bind "${mise_root}" "/home/${current_user}/.local/share/mise" \
  --ro-bind "${mise_config_dir}" "/home/${current_user}/.config/mise" \
  --bind "${project_root}" "${project_root}" \
  "${git_metadata_binds[@]}" \
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
  --setenv MISE_CACHE_DIR "${mise_cache_root}" \
  --setenv MISE_STATE_DIR "/home/${current_user}/.local/state/mise" \
  --setenv RUSTUP_HOME "/home/${current_user}/.local/share/mise/rustup-home" \
  --setenv CARGO_HOME "/home/${current_user}/.cargo" \
  --setenv NIX_LD "${nix_ld}" \
  --setenv NIX_LD_LIBRARY_PATH "${nix_ld_library_path}" \
  --setenv SSL_CERT_FILE "${ssl_cert_file}" \
  "${terminal_env_args[@]}" \
  "${mise_state_bind[@]}" \
  "${store_ro_binds[@]}" \
  "${task_library_binds[@]}" \
  "${task_library_env[@]}" \
  -- \
  "${sandbox_target}" "$@"
